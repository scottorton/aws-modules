# aws-modules

A collection of reusable Terraform modules for AWS.

## Modules

### `darts-ladder`

Deploys a containerised Flask darts ladder application on AWS ECS Fargate, fronted
by an Application Load Balancer and backed by DynamoDB. It builds into an existing
VPC and subnets rather than creating its own networking.

**What it creates**

| Area | Resources |
| --- | --- |
| Data storage | Two on-demand (`PAY_PER_REQUEST`) DynamoDB tables: `DartsLadder` (hash key `id`) and `DartsMatches` (hash key `match_id`) |
| Container registry | An ECR repository named after `app_name`, with mutable tags and scan-on-push enabled |
| Networking | Two security groups in the existing VPC: an ALB group allowing HTTP/80 from anywhere, and an ECS group allowing port 5000 only from the ALB |
| Load balancing | An internet-facing ALB, an IP target group on port 5000 with a `/` health check, and an HTTP listener on port 80 forwarding to it |
| IAM | An ECS execution role (with `AmazonECSTaskExecutionRolePolicy`) and a task role granted scoped read/write access to the two DynamoDB tables |
| Compute | An ECS cluster, a Fargate task definition (256 CPU / 512 MB, `awsvpc`, image `<ecr-repo>:latest`, container port 5000), and an ECS service running one task behind the ALB |
| Logging | A CloudWatch log group `/ecs/<app_name>` with 7-day retention |

**Inputs**

| Name | Type | Description |
| --- | --- | --- |
| `aws_region` | `string` | Region passed to the container as `AWS_REGION` and used for log configuration |
| `app_name` | `string` | Name prefix applied to the ECR repo, cluster, service, roles, security groups, and ALB |
| `existing_vpc_id` | `string` | ID of the existing VPC to build into |
| `existing_subnet_ids` | `list(string)` | At least two existing public subnet IDs for the ALB and ECS tasks |

**Notes**

- Tasks run with `assign_public_ip = true`, so the subnets must be public (or otherwise
  have a route to the internet) for image pulls to succeed.
- The listener is HTTP-only; there is no TLS/HTTPS listener or certificate.
- The DynamoDB table names are fixed, so the module can only be deployed once per account
  and region as written.
- The task definition expects an image already pushed to the ECR repository under the
  `latest` tag.
