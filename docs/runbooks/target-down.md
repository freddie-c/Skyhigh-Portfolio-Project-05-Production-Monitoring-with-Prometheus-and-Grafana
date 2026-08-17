# Alert: Target Down

**Severity:** critical
**Fires when:** Prometheus fails to scrape a target for 1 minute
**Source:** Prometheus rule `TargetDown` in node_alerts.yml
**Expression:** up == 0

## What this means

Prometheus generates the `up` metric itself on every scrape attempt:
1 if the target responded, 0 if it did not. This alert means a
target has stopped responding entirely.

Critically, this does not distinguish between "the host is down"
and "node_exporter is down on a healthy host." Both look identical
from Prometheus. Determining which is the first job.

## Impact

You are now blind to that host. Every other alert for it — CPU,
disk, memory — is silently inoperative, because there is no data
to evaluate. A host that has stopped reporting is not a healthy
host, and treating missing data as "fine" is how outages go
unnoticed for 45 minutes.

## Immediate checks

1. Confirm which target and how long:
   http://<monitor-ip>:9090/targets
   The failing target shows DOWN with an error message. Read it —
   "connection refused" and "context deadline exceeded" mean
   different things.

2. Is the instance running at all?
   aws ec2 describe-instance-status --instance-ids <id> --region us-east-1
   If the instance is stopped or terminated, that is the answer.

3. If the instance is running, connect:
   aws ssm start-session --target <instance-id>
   If SSM cannot connect either, the host itself is unhealthy —
   skip to escalation.

4. Check the exporter:
   sudo systemctl status node_exporter
   curl -s http://localhost:9100/metrics | wc -l
   Expected: active (running), 1000+ lines.

## Common causes

**Instance stopped or terminated** — check step 2 first, it is the
fastest to rule out.
Error signature: connection refused or no route to host.

**node_exporter crashed or stopped** — the service is not running
on an otherwise healthy host.
Confirm: systemctl status shows failed or inactive.
Note: the unit has Restart=on-failure, so a crash should self-heal.
If it did not, the process exited cleanly or the restart is failing.

**Security group change** — someone modified the target SG and the
9100 rule from the monitor's SG was removed.
Confirm: aws ec2 describe-security-groups --group-ids <target-sg>

**Private IP changed** — prometheus.yml uses a static IP. If the
instance was replaced, the IP in the scrape config is stale.
Confirm: compare terraform output target_private_ip against
prometheus.yml.
Error signature: connection timeout, not refused.

**Host resource exhaustion** — the host is up but too loaded to
respond within the scrape timeout.
Confirm: check the last known values on the dashboard before the
gap started.

## Resolution

Instance stopped: start it. node_exporter is enabled, so it returns
automatically on boot.

node_exporter down: sudo systemctl start node_exporter, then check
journalctl -u node_exporter -n 50 to find out why it stopped.

Security group: restore the inbound 9100 rule sourced from the
monitor's security group. Use the security group ID, not an IP.

Stale IP: update the target in prometheus.yml and restart the
Prometheus container. Longer term, this is why static targets are
a known limitation — EC2 service discovery would prevent it.

## Known limitation

This stack uses static scrape targets. Any instance replacement
requires a manual prometheus.yml edit. A production deployment
would use ec2_sd_config with tag-based discovery, which finds
targets automatically and removes this failure mode entirely.

## If none of the above

Capture before escalating:
- The exact error text from the Prometheus targets page
- Instance state from describe-instance-status
- Whether SSM can connect
- Time the gap started (visible on any dashboard panel)

Escalate to: Skyhigh Dev/Ops Cloud Engineer - Freddie C.

## Related

- Dashboard: SkyHigh Production Monitoring — all panels will show
  a gap starting at the failure time
- Runbook: monitoring-stack-down.md