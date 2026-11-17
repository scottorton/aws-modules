variable "name" {
  type        = string
  description = "Name prefix for the shared resources (cluster, ALB, security groups, execution role)."
}

variable "vpc_id" {
  type        = string
  description = "The ID of your existing VPC."
}

variable "subnet_ids" {
  type        = list(string)
  description = "At least two existing public subnet IDs (used by the ALB and the tasks)."
}

variable "apps" {
  description = <<-EOT
    Map of apps to run on the shared cluster behind the shared ALB. The map key is the app name.
    Only `port` is required. Routing: set `hosts` (host-header routing) and/or `paths`
    (path routing). If neither is set, the app is routed on "/<key>" and "/<key>/*".
  EOT

  type = map(object({
    port              = number
    cpu               = optional(number, 256)
    memory            = optional(number, 512)
    desired_count     = optional(number, 1)
    image             = optional(string) # defaults to a module-created ECR repo, tag :latest
    hosts             = optional(list(string))
    paths             = optional(list(string))
    priority          = optional(number) # listener rule priority; auto-assigned if omitted
    health_check_path = optional(string, "/")
    environment       = optional(map(string), {})
    task_policy_arns  = optional(list(string), [])
  }))
}
