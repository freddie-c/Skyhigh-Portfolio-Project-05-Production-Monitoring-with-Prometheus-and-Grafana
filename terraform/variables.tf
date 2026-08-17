variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names and the Project tag"
  type        = string
  default     = "skyhigh-monitoring"
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.42/32"
  type        = string # Must be /32 to allow only your single IP address, not a range

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) # Validates that the input is a valid CIDR notation
    error_message = "my_ip must be valid CIDR notation, including the /32 suffix."
  }
}

variable "instance_type" {
  description = "EC2 instance type for both servers"
  type        = string
  default     = "t2.micro"
}

variable "ssm_parameter_path" {
  description = "Parameter Store path prefix holding this project's secrets"
  type        = string
  default     = "/skyhigh/monitoring" # The path prefix in SSM Parameter Store where secrets are stored, e.g., /skyhigh/monitoring
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications"
  type        = string
}