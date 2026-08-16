output "monitor_public_ip" {
  description = "Open Grafana at http://<this>:3000 and Prometheus at :9090"
  value       = aws_instance.monitor.public_ip
}

output "monitor_instance_id" {
  description = "For: aws ssm start-session --target <this>"
  value       = aws_instance.monitor.id
}

output "target_instance_id" {
  description = "For: aws ssm start-session --target <this>"
  value       = aws_instance.target.id
}

output "target_private_ip" {
  description = "Goes into prometheus.yml as <this>:9100"
  value       = aws_instance.target.private_ip # PRIVATE, not public — traffic stays in the VPC
}

output "cloudwatch_alarm_dimension" {
  description = "InstanceId for the monitor-the-monitor alarm in Phase 7"
  value       = aws_instance.monitor.id
}