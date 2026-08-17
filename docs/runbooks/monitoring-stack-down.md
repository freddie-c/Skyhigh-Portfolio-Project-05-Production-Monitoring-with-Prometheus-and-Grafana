# Runbook: Monitoring Stack Down

**Severity:** critical
**Fires when:** CloudWatch alarm on monitor CPU, OR no alerts
received when expected, OR dashboard unreachable
**Source:** CloudWatch alarm `skyhigh-monitoring-monitor-cpu-high`
via SNS email

## What this means

The monitoring stack itself is degraded or down. This is the one
failure Grafana cannot alert you about, because Grafana is the
thing that is broken.

CloudWatch is the outside observer. It collects EC2 metrics at the
hypervisor level, independent of anything running on the instance,
so it still sees the host even when the host cannot report on
itself. That is why this alarm exists and why its notification path
(SNS email) is completely separate from the Grafana contact point.

## Impact

Every other alert in this document is now inoperative. CPU, disk,
and target-down alerts will not fire regardless of what happens on
the monitored hosts. You are blind, and unlike the target-down case,
nothing will tell you.

The dangerous property: a broken monitoring system looks exactly
like a healthy environment. No alerts arrive either way.

## How you might notice

1. CloudWatch alarm email arrives (the designed path)
2. Dashboard will not load at http://<monitor-ip>:3000
3. Alerts stopped arriving and you expected some
4. Prometheus targets page unreachable at :9090

## Immediate checks

1. Is the instance running?
   aws ec2 describe-instance-status --instance-ids <monitor-id> --region us-east-1

2. Can you reach it at all?
   aws ssm start-session --target <monitor-id>
   If SSM fails, the host is unhealthy or the SSM agent is starved
   of CPU. Skip to "Host unresponsive" below.

3. Are the containers running?
   docker compose -f ~/monitoring/docker-compose.yml ps
   Expected: prometheus and grafana both "Up".

4. Check host resources:
   uptime
   df -h /
   free -h
   A full disk will take down both containers.

5. Check container health:
   curl -s http://localhost:9090/-/healthy
   curl -s http://localhost:3000/api/health

## Common causes

**Your public IP changed** — the most common cause, and it is not
an outage at all. The security group allows 3000 and 9090 from a
single /32. Residential IPs rotate.
Confirm: curl -s https://checkip.amazonaws.com and compare against
terraform.tfvars.
Signature: dashboard unreachable from your machine, but the stack
is healthy and alerts still fire.

**Disk full on the monitor** — Prometheus TSDB growth with
retention set too long for the volume.
Confirm: df -h /
Signature: both containers unhealthy or restarting.

**Container crashed** — check docker compose ps and logs.
Note: restart policy is unless-stopped, so a crash should self-heal.
If it did not, the container is in a crash loop.

**Instance stopped** — someone stopped it, or it was stopped at the
end of a work session and not restarted.

**Host CPU exhausted** — the CloudWatch alarm's designed trigger.
Something on the monitor is consuming all CPU, starving the
containers and the SSM agent.

## Resolution

Public IP changed:
  curl -s https://checkip.amazonaws.com
  Update my_ip in terraform.tfvars, then terraform apply.
  This is not an incident. Consider it a known operational quirk
  of restricting access by source IP.

Disk full: see low-disk-space.md. On this host specifically,
Prometheus TSDB is the likely consumer. Reduce retention in
docker-compose.yml or grow the volume.

Container crashed:
  docker compose -f ~/monitoring/docker-compose.yml logs --tail 100
  docker compose -f ~/monitoring/docker-compose.yml up -d

Instance stopped:
  aws ec2 start-instances --instance-ids <monitor-id>
  Wait 2-3 minutes. Containers restart automatically via the
  restart policy. Note the public IP will have changed.

Host unresponsive: stop and start the instance. This is a last
resort but recovers a host too starved to accept SSM connections.

## Verifying recovery

Do not assume it is fixed because the dashboard loads. Confirm the
full pipeline:

1. Both containers up:
   docker compose ps
2. Both scrape targets healthy:
   curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[^"]*"'
   Expected: two results, both "up"
3. Dashboard renders with current data (check the timestamp on the
   CPU panel — a gap means Prometheus was down and that window is
   permanently lost)
4. Send a test notification from Grafana to the contact point

## Known gap

There is no alert for "Prometheus is running but not scraping."
The CloudWatch alarm watches CPU only. A Prometheus process that is
alive but failing every scrape would not trigger it.

Mitigations worth considering:
- CloudWatch alarm on StatusCheckFailed for the monitor instance
- An external uptime check against the Grafana health endpoint
- Prometheus federation or a second Prometheus scraping the first

This is documented rather than implemented because it is beyond the
scope of a single-host lab, but it is a real gap in production.

## Related

- CloudWatch alarm: skyhigh-monitoring-monitor-cpu-high
- SNS topic: skyhigh-monitoring-alerts
- All other runbooks depend on this stack being operational