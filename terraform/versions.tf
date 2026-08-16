terraform {
  required_version = ">= 1.5" # Blocks Terraform versions below 1.5

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Official AWS provider, maintained by HashiCorp
      version = "~> 5.0"        # Locks to the 5.x series, which is the current major version as of 2024-06
    }
  }
}

provider "aws" {
  region = var.aws_region # The AWS region to create resources in, e.g. us-east-1

  default_tags { # Tags applied to every resource, unless overridden
    tags = {
      Project     = var.project_name # Prefix for resource names and the Project tag
      ManagedBy   = "Terraform"      # Indicates this resource is managed by Terraform
      Environment = "lab"
    }
  }
}