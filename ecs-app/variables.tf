
variable "aws_region" {
  type = string

}

variable "app_name" {
  type = string

}

variable "vpc_id" {
  type        = string
  description = "The ID of your existing VPC"
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of at least two existing public subnet IDs"
}
