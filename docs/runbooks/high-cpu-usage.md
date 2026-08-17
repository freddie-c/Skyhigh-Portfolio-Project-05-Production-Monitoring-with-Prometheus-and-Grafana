# Alert: High CPU Usage

**Severity:** warning
**Fires when:** CPU utilization above 80% for 2 consecutive minutes
**Source:** Grafana rule `High CPU Usage` (folder: SkyHigh)
**Also monitored by:** Prometheus rule `HighCPUUsage` in node_alerts.yml

## What this means

A monitored host has been running above 80% CPU for at least two
minutes. The 2-minute pending period means this is sustained load,
not a transient spike from a cron job or deploy.

## Impact

Depends on the host. Sustained high CPU degrades response times
before it causes outright failure — users typically notice slowness
before anything breaks. On a 1-vCPU instance there is no headroom,
so treat this as more urgent than the same alert on a larger host.

## Immediate checks

1. Confirm the alert is real and current:
   Open the SkyHigh Production Monitoring dashboard, CPU Usage panel.
   Expected: line at or near the threshold. If it has already
   dropped, the alert is resolving on its own.

2. Identify the host from the alert's `instance` label, then connect:
   aws ssm start-session --target <instance-id>

3. Find what is consuming CPU:
   top -b -n 1 | head -20
   Expected: one or more processes with high %CPU.

4. Check load relative to core count:
   uptime
   nproc
   Load above core count means processes are queuing, not just busy.

## Common causes

**Runaway or stuck process** — most common. A process in a tight
loop, a hung request handler, a runaway script.
Confirm: top shows a single process at or near 100%.

**Legitimate load increase** — traffic grew, a batch job is running.
Confirm: multiple processes busy, load roughly matches expected work.

**Load testing or maintenance** — someone is deliberately generating
load. Confirm: check with the team before killing anything.

**Undersized instance** — the alert fires regularly under normal
traffic. Confirm: check the CPU panel over the last 7 days.

## Resolution

Runaway process: identify the PID from top, confirm what it is
(ps -fp <PID>), then kill it. Restart the service properly rather
than leaving it dead.

Legitimate load: no immediate action. If sustained, the host needs
more capacity — this is a scaling conversation, not an incident.

Maintenance: acknowledge the alert. Consider a silence in Grafana
for the duration of planned work.

Undersized: schedule an instance resize. Document the pattern
before proposing it.

## If none of the above

Capture before escalating:
- Output of top -b -n 1 | head -30
- Output of uptime and nproc
- Screenshot of the CPU panel over the last 6 hours
- The alert payload from the contact point

Escalate to: Skyhigh Dev/Ops Cloud Engineer - Freddie C.

## Related

- Dashboard: SkyHigh Production Monitoring
- Runbook: monitoring-stack-down.md (if the dashboard is unreachable)