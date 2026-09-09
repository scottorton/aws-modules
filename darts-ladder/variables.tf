
variable "aws_region" {
  type = string

}

variable "app_name" {
  type = string

}

variable "existing_vpc_id" {
  type        = string
  description = "The ID of your existing VPC (e.g., vpc-0123456789abcdef0)"
}

variable "existing_subnet_ids" {
  type        = list(string)
  description = "A list of at least two existing public subnet IDs (e.g., [\"subnet-abc123\", \"subnet-def456\"])"
}
