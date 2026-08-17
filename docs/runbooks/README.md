# Runbooks

Operational procedures for alerts fired by the SkyHigh monitoring stack.

| Alert | Severity | Source | Runbook |
|---|---|---|---|
| High CPU Usage | warning | Grafana | [high-cpu-usage.md](high-cpu-usage.md) |
| Low Disk Space | critical | Grafana | [low-disk-space.md](low-disk-space.md) |
| Target Down | critical | Prometheus | [target-down.md](target-down.md) |
| Monitoring Stack Down | critical | CloudWatch | [monitoring-stack-down.md](monitoring-stack-down.md) |

## If the dashboard will not load

Check [monitoring-stack-down.md](monitoring-stack-down.md) first.
The most common cause is a changed source IP, not an outage.

## Escalation

Escalate to: Skyhigh Dev/Ops Cloud Engineer - Freddie C.