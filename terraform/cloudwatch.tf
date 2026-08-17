resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts" # skyhigh-monitoring-alerts
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # Requires a click in your inbox to confirm
}

resource "aws_cloudwatch_metric_alarm" "monitor_cpu_high" {
  alarm_name        = "${var.project_name}-monitor-cpu-high"
  alarm_description = "Monitor host CPU above 90% for 5 minutes - the monitoring stack itself may be degraded"

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  dimensions = {
    InstanceId = aws_instance.monitor.id # Watches the MONITOR, not the target
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 90
  period              = 300 # 5 min - matches basic monitoring's publish rate
  evaluation_periods  = 1   # One 5-minute period over threshold fires it

  treat_missing_data = "breaching" # No data = assume broken, not healthy

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn] # Also notify on recovery
}