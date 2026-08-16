resource "aws_iam_role" "instance" {
  name = "${var.project_name}-instance-role"

  assume_role_policy = jsonencode({ # WHAT can assume this role — in this case, EC2 instances. The policy is in JSON format, which is why we use jsonencode() to convert the HCL representation into JSON.
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com" # Only the EC2 service — not users, not other accounts
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # AWS-managed: Session Manager
}

resource "aws_iam_role_policy" "parameter_access" {
  name = "${var.project_name}-parameter-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({ # WHAT the role may do
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",       # Read one parameter
          "ssm:GetParameters",      # Read several in one call
          "ssm:GetParametersByPath" # Read everything under the path prefix
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_path}/*"
      }, # ^ Scoped to /skyhigh/monitoring/* — nothing else in the account
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"                         # Required separately: SecureString is KMS-encrypted
        Resource = data.aws_kms_alias.ssm.target_key_arn # Grants decryption of the AWS-managed KMS key used by SSM for SecureStrings
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance.name # The instance profile is what EC2 instances actually attach to, and it contains the IAM role that defines the permissions.
}