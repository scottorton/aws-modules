data "aws_region" "current" {}

locals {
  region   = data.aws_region.current.region
  app_keys = sort(keys(var.apps))

  apps = {
    for k, a in var.apps : k => merge(a, {
      image    = coalesce(a.image, "${try(aws_ecr_repository.app[k].repository_url, "")}:latest")
      paths    = a.hosts == null && a.paths == null ? ["/${k}", "/${k}/*"] : a.paths
      priority = coalesce(a.priority, 100 + index(local.app_keys, k) * 10)
    })
  }

  task_policy_attachments = merge([
    for k, a in var.apps : { for arn in a.task_policy_arns : "${k}|${arn}" => { app = k, arn = arn } }
  ]...)
}

# ------------------------------------------------------------------------------
# Shared: Security Groups
# ------------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Allow inbound HTTP to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Tasks only accept traffic from the ALB (any port, so every app is covered).
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# Shared: Application Load Balancer + listener
# ------------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

# ------------------------------------------------------------------------------
# Shared: ECS Cluster + execution role
# ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = var.name
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------------------------------------------------------------------------
# Per app
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  for_each = { for k, a in var.apps : k => a if a.image == null }

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_cloudwatch_log_group" "app" {
  for_each = var.apps

  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = 7
}

resource "aws_iam_role" "task" {
  for_each = var.apps

  name               = "${var.name}-${each.key}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = local.task_policy_attachments

  role       = aws_iam_role.task[each.value.app].name
  policy_arn = each.value.arn
}

resource "aws_lb_target_group" "app" {
  for_each = local.apps

  name        = "${var.name}-${each.key}-tg"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "app" {
  for_each = local.apps

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  dynamic "condition" {
    for_each = each.value.hosts == null ? [] : [each.value.hosts]
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.paths == null ? [] : [each.value.paths]
    content {
      path_pattern {
        values = condition.value
      }
    }
  }
}

resource "aws_ecs_task_definition" "app" {
  for_each = local.apps

  family                   = "${var.name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = each.value.image
    essential = true

    portMappings = [{
      containerPort = each.value.port
      hostPort      = each.value.port
      protocol      = "tcp"
    }]

    environment = [
      for name, value in merge({ AWS_REGION = local.region }, each.value.environment) :
      { name = name, value = value }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app[each.key].name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  for_each = local.apps

  name            = each.key
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  depends_on = [aws_lb_listener_rule.app]
}
