# Alert: Low Disk Space

**Severity:** critical
**Fires when:** Root filesystem above 90% used (no pending period)
**Source:** Grafana rule `Low Disk Space` (folder: SkyHigh)
**Also monitored by:** Prometheus rule `LowDiskSpace` in node_alerts.yml

## What this means

The root filesystem on a monitored host is above 90% capacity.
Unlike CPU, this does not resolve itself — disk usage only grows
unless something is removed. There is no pending period on this
alert because a full disk is immediately actionable.

## Impact

At 100% the host stops accepting writes. Applications fail in
confusing ways: databases refuse transactions, logs stop writing,
package managers fail, and SSH sessions may not open because they
cannot write to a session file. The failure mode is broad and the
error messages rarely say "disk full."

This is the alert that caused two outages before monitoring existed.

## Immediate checks

1. Confirm current usage:
   df -h /
   Expected: Use% at or above 90%.

2. Find the largest consumers:
   sudo du -h --max-depth=1 / 2>/dev/null | sort -rh | head -10
   Then drill into whichever directory dominates.

3. Check for deleted-but-open files:
   sudo lsof +L1 2>/dev/null | head -20
   A file deleted while a process holds it open still consumes
   space until that process closes it. df shows the space used;
   du does not. If df and du disagree substantially, this is why.

## Common causes

**Log growth** — most common. An application logging at debug level,
or a log file with no rotation.
Confirm: /var/log dominates the du output.

**Container images and volumes** — on Docker hosts, unused images
and stopped containers accumulate.
Confirm: docker system df

**Prometheus TSDB growth** — on the monitoring host specifically.
Retention is set to 15 days in docker-compose.yml.
Confirm: docker system df, look at volume sizes.

**A large file someone left behind** — backups, core dumps, test
artifacts in /tmp or /var/tmp.
Confirm: the du walk in step 2.

## Resolution

Do NOT start deleting files before step 3. Removing a file that a
running process holds open frees nothing, and deleting the wrong
file can take down the service you are trying to save.

Log growth: rotate rather than delete. Check whether logrotate is
configured for that path. If truncating an active log, use
truncate -s 0 <file> rather than rm — deleting a file the process
has open leaves the space allocated.

Docker: docker system prune removes stopped containers, unused
networks, and dangling images. Add -a to include unused images.
Review what it will remove before confirming.

Prometheus TSDB: if this is the cause, retention is too long for
the volume size. Reduce --storage.tsdb.retention.time or grow the
volume. This is a configuration change, not a cleanup.

Deleted-but-open files: restart the process holding the handle.

## If none of the above

Capture before escalating:
- df -h output
- The du walk from step 2
- lsof +L1 output
- Screenshot of the Disk usage panel over the last 7 days
  (is this sudden or gradual?)

Sudden growth suggests a specific event. Gradual growth suggests
the host is simply undersized for its retention settings.

Escalate to: Skyhigh Dev/Ops Cloud Engineer - Freddie C.

## Related

- Dashboard: SkyHigh Production Monitoring, "Disk usage by mount"
- Runbook: monitoring-stack-down.md