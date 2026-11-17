# aws-modules

A collection of reusable Terraform modules for AWS.

## Modules

### `ecs-app`

Runs one or more containerised apps on a **shared** ECS Fargate cluster behind a **shared**
Application Load Balancer, inside an existing VPC. One module call = one cluster + one ALB;
each entry in `apps` gets its own task definition, service, target group, listener rule,
task role, log group, and (unless you pass `image`) ECR repository.

**Usage**

```hcl
module "ecs" {
  source     = "git::https://github.com/scottorton/aws-modules.git//ecs-app"
  name       = "shared"
  vpc_id     = "vpc-0123456789"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  apps = {
    darts = { port = 5000 }                                   # routed on /darts, /darts/*
    api   = { port = 8080, hosts = ["api.example.com"] }      # routed by host header
  }
}
```

**Inputs**

| Name | Type | Description |
| --- | --- | --- |
| `name` | `string` | Prefix for the shared cluster, ALB, security groups and execution role |
| `vpc_id` | `string` | Existing VPC ID |
| `subnet_ids` | `list(string)` | At least two public subnet IDs |
| `apps` | `map(object)` | Apps keyed by name. Only `port` is required |

Optional per-app fields: `cpu` (256), `memory` (512), `desired_count` (1), `image`
(defaults to `<ecr-repo>:latest`), `hosts`, `paths`, `priority` (auto), `health_check_path`
(`/`), `environment` (map), `task_policy_arns` (list).

**Outputs:** `alb_dns_name`, `alb_zone_id`, `cluster_name`, `ecr_repository_urls`, `service_names`.

**Notes**

- If an app sets neither `hosts` nor `paths`, it is routed on `/<key>` and `/<key>/*`; the
  app itself must serve under that prefix. Unmatched requests get a 404 from the ALB.
- Listener is HTTP-only on port 80.
- Target group names are `<name>-<key>-tg` and must stay within AWS's 32-character limit.
- Region is taken from the provider; `AWS_REGION` is injected into every container.
