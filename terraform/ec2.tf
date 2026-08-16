resource "aws_instance" "monitor" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.monitor.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name # Grants SSM + parameter access

  associate_public_ip_address = true # Outbound only — SG allows nothing inbound but 3000/9090

  # key_name intentionally omitted        # No SSH key exists — access is SSM only

  metadata_options {
    http_tokens                 = "required" # IMDSv2 mandatory — blocks the SSRF credential-theft path
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1 # Metadata unreachable from inside containers
  }

  root_block_device {
    volume_size = 20    # 8 GB default is tight once Prometheus TSDB grows
    volume_type = "gp3" # Cheaper and faster than gp2, same price tier
    encrypted   = true  # Encryption at rest, free, no reason not to
  }

  tags = { Name = "skyhigh-monitor" }
}

resource "aws_instance" "target" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id # Same subnet as monitor — private IP reachable
  vpc_security_group_ids = [aws_security_group.target.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  associate_public_ip_address = true # Outbound only — SG allows nothing inbound but 9100

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 8 # 8 GB default is fine for the target — no Prometheus TSDB here
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "skyhigh-target" }
}