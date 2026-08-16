locals {
  subnet_id = sort(data.aws_subnets.default.ids)[0] # Deterministic pick — both boxes land in the SAME subnet
}

resource "aws_security_group" "monitor" {
  name        = "${var.project_name}-monitor-sg"
  description = "Grafana and Prometheus UIs, restricted to operator IP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip] # Grafana has NO auth — this rule is the only control
  }

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.my_ip] # Prometheus has NO auth — this rule is the only control
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Allows all outbound traffic, which is necessary for the monitor instance to reach external services like SSM, Docker Hub, and SES.
    cidr_blocks = ["0.0.0.0/0"] # SSM agent tunnel + dnf package installs
  }

  tags = { Name = "${var.project_name}-monitor-sg" }
}

resource "aws_security_group" "target" {
  name        = "${var.project_name}-target-sg"
  description = "Node Exporter, reachable only from the monitor"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Node Exporter metrics from monitor"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor.id] # Only the monitor SG can reach this port — no public access
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # SSM agent tunnel + dnf package installs
  }

  tags = { Name = "${var.project_name}-target-sg" }
}