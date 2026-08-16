data "aws_caller_identity" "current" {} # Returns the AWS account ID, user ID, and ARN of the caller. This is useful for constructing ARNs and other resource identifiers that require the account ID.

data "aws_vpc" "default" {
  default = true # Returns the default VPC in the region. This is useful for creating resources in the default VPC without needing to specify its ID explicitly.
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id] # Filters the subnets to only those that belong to the default VPC.
  }
}

data "aws_ami" "al2023" {
  most_recent = true       # Returns the most recent Amazon Linux 2023 AMI. 
  owners      = ["amazon"] # Limits the search to AMIs owned by Amazon, ensuring that you get an official Amazon Linux 2023 image.

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"] # AL2023, x86_64 — matches t2.micro's architecture
  }
}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm" # Returns the KMS key used by AWS Systems Manager (SSM) for encrypting parameters in Parameter Store. This is useful for granting decryption permissions to EC2 instances that need to access secure parameters.
}