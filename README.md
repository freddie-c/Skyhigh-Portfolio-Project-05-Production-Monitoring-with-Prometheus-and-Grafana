# SkyHigh Portfolio Project 05 — Production Monitoring with Prometheus and Grafana

## Project Description

I built a complete monitoring stack from an empty directory: Terraform-provisioned infrastructure with zero inbound SSH, a hardened Node Exporter service, Prometheus scraping across a VPC, a five-panel Grafana dashboard provisioned from version control, three layers of alerting, and operational runbooks for every alert that can fire.

**The scenario:** An operations team has been running a production web app for three months with no dashboards and no alerts. Engineers find out about problems when customers complain on social media — by then the incident is 45 minutes old. Deployments cause CPU spikes nobody catches. The database server has silently filled its disk twice, causing two outages. Nobody knows what "normal" traffic looks like. The mandate: *build us eyes — real-time visibility, dashboards anyone can open during an incident, and alerts that page us before customers notice. Pick the tools, build the stack, write the runbooks.*

**Result:** Two EC2 instances with no SSH port open on either, secrets that never touch git or Terraform state, a dashboard that survives a total volume wipe because it lives in the repo, and an alert path proven end to end by pinning a CPU at 100% and watching the notification arrive.

**Built with:** Terraform · AWS EC2 · AWS Systems Manager (Session Manager + Parameter Store) · IAM · CloudWatch · SNS · Docker Compose · Prometheus · Node Exporter · Grafana · systemd

---

## What You'll Learn

- Why Prometheus is **pull-based** and what that costs you: the monitor holds the target list, so an unreachable target is itself a signal (`up == 0`) — but a target behind NAT cannot be scraped at all
- Reach EC2 instances with **zero inbound SSH** using SSM Session Manager, where the instance dials out over 443 and every session is attributed to an IAM identity in CloudTrail
- Keep secrets out of `terraform.tfstate` entirely — `sensitive = true` only masks console output, the value is still plaintext JSON in state
- Give an instance read-only access to its own credentials via SSM Parameter Store, and understand why `kms:Decrypt` is a **separate** permission from `ssm:GetParameter`
- Turn `nohup ./binary &` into a real systemd service: dedicated no-login user, `Restart=on-failure`, and filesystem hardening with `ProtectSystem`, `ProtectHome`, `PrivateTmp`, and `NoNewPrivileges`
- Write the PromQL that actually matters: why `rate(node_cpu_seconds_total{mode="idle"}[5m])` is the standard CPU query, and why `MemAvailable` — not `MemFree` — is the correct memory metric on Linux
- Provision Grafana **as code** so a `docker volume rm` doesn't destroy your dashboards — and discover that an exported dashboard's `${DS_PROMETHEUS}` input variable does not resolve when provisioned from file
- Tune alert timing to the failure mode: a 2-minute pending period for CPU (spikes self-resolve), zero for disk (a full disk does not drain itself)
- Understand why a 5-minute `rate()` window means your alert takes four minutes to fire and three minutes to clear — and why a 300-second load test isn't long enough to prove it
- Build the **"monitor the monitor"** layer: CloudWatch observes EC2 at the hypervisor level, independent of anything running on the instance, because Grafana cannot alert you that Grafana is down
- Recognize that `git` is a better file-transfer mechanism than a terminal clipboard once you're past a few kilobytes

---

## Proof of Production

**1. Both scrape targets healthy**

Screenshot here

Prometheus scraping itself and the target across the VPC. Note the scrape durations — 4.7ms for localhost, 85.6ms for the cross-instance target. That gap is real network round-trip and it's the baseline to compare against when something degrades.

**2. Five-panel dashboard, live data**

Screenshot here

CPU, memory, disk by mount, network throughput, and system load. Memory top-left because that's where eyes land first during an incident. Every query written by hand — no imported community dashboard.

**3. Dashboard survives a total volume wipe**

Screenshot here

`docker compose down && docker volume rm monitoring_grafana-data && docker compose up -d` destroys Grafana's entire database. The dashboard and datasource come back anyway, because they're provisioned from files in this repository. That is the difference between "I set up Grafana" and "I can redeploy this stack from scratch."

**4. node_exporter surviving a reboot with nobody logged in**

Screenshot here

`uptime` reports 5 minutes and **0 users**, and the exporter is serving 2,184 metrics. With `nohup ./node_exporter &`, those two facts are mutually exclusive.

**5. Alert firing end to end**

Screenshot here

`stress-ng --cpu 4` on the target → CPU pinned at 100% → Grafana rule Normal → Pending → Firing → webhook POST received in 0.001s, with the `{{ $labels.instance }}` template rendered to the actual host. The Pending state is the interesting one: the threshold was crossed but the rule waited two full minutes to confirm it was sustained.

**6. Two independent alerting systems catching the same condition**

Grafana rules and Prometheus-native rules both fired on the same CPU spike. Prometheus rules keep evaluating if Grafana is down; Grafana rules give you contact-point routing. Running both is defense in depth.

---

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │  Operator (source IP /32 only)          │
                    └───────┬─────────────────────┬───────────┘
                            │ :3000 :9090         │ SSM (443 outbound)
                            ▼                     ▼
┌───────────────────────────────────────────────────────────────────┐
│ VPC (default) — us-east-1                                         │
│                                                                   │
│  ┌──────────────────────────────┐      ┌───────────────────────┐  │
│  │ skyhigh-monitor  (t2.micro)  │      │ skyhigh-target        │  │
│  │ SG: 3000, 9090 from /32      │      │ SG: 9100 from         │  │
│  │ NO PORT 22                   │      │     monitor-sg        │  │
│  │                              │      │ NO PORT 22            │  │
│  │  ┌────────────┐ ┌──────────┐ │      │                       │  │
│  │  │ Prometheus │ │ Grafana  │ │      │  node_exporter        │  │
│  │  │ :9090      │ │ :3000    │ │      │  :9100                │  │
│  │  │ 15d TSDB   │ │ 5 panels │ │      │  systemd, hardened    │  │
│  │  └─────┬──────┘ └────┬─────┘ │      │  non-root service user│  │
│  │        │             │       │      └───────────┬───────────┘  │
│  │        └─── scrape ──┼───────┼──────────────────┘              │
│  │             15s      │       │   172.31.x.x:9100 (private)     │
│  └──────────────────────┼───────┘                                 │
└─────────────────────────┼─────────────────────────────────────────┘
                          │                    ▲
              webhook     │                    │ CloudWatch (hypervisor-level)
              contact pt  ▼                    │ CPU > 90% for 5m
                    [ alert sink ]             ▼
                                          SNS → email
```

**Data flow:**

1. `node_exporter` reads `/proc` and `/sys` on the target and exposes ~2,200 metrics on port 9100. It never sends anything — it waits to be asked.
2. Prometheus scrapes it every 15 seconds over the **private** IP, so traffic never leaves the VPC. The target's security group permits this by referencing the monitor's *security group ID*, not an IP address.
3. Prometheus stores the samples in a local TSDB with 15-day retention and evaluates three native alert rules against them.
4. Grafana queries Prometheus through Docker's internal network (`http://prometheus:9090`) and evaluates two alert rules on a 1-minute interval.
5. Firing alerts POST to a webhook contact point.
6. Independently, CloudWatch watches the monitor's own CPU from outside the instance and notifies via SNS email — the layer that still works when the monitoring host itself is the problem.

---

## Prerequisites

| Tool | Version used | Install |
|---|---|---|
| AWS account | with an IAM identity that can create EC2, IAM, SSM, SNS, CloudWatch | — |
| Terraform | >= 1.5 | `brew install terraform` |
| AWS CLI v2 | configured profile | `brew install awscli` |
| Session Manager plugin | for `aws ssm start-session` | [AWS docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) |
| A webhook sink | webhook.site, or substitute your own | — |

**Required before `terraform apply`** — create the Grafana admin password as a SecureString by hand. Terraform never sees it:

```bash
read -s "PW?Grafana admin password: "
aws ssm put-parameter \
  --name "/skyhigh/monitoring/grafana-admin-password" \
  --value "$PW" --type SecureString --region us-east-1
unset PW
```

Note `read -s`: the password is never echoed, never lands in shell history, and never appears in a command argument.

---

## Tech Stack

| Technology | Role in this project | Why I chose it |
|---|---|---|
| Terraform | All AWS infrastructure | The one thing in this build I created by hand — an SES IAM user — took six commands to delete because I had to unwind its dependencies manually. Terraform tracks that graph for you |
| SSM Session Manager | Instance access | The instance dials out over 443, so there is no inbound SSH, no key pair to lose, and every session is attributed to an IAM principal in CloudTrail |
| SSM Parameter Store | Secret storage | SecureString parameters are KMS-encrypted, and the instance reads them with its role — no credential is stored on the host or in state |
| Node Exporter v1.8.2 | Host metrics | The de-facto standard; pinned rather than `latest` so the build is reproducible, and checksum-verified before installation |
| systemd | Process supervision | `Restart=on-failure` and `WantedBy=multi-user.target` are the difference between a process and a service |
| Prometheus v2.54.1 | Metrics + alert evaluation | Pull-based collection means a missing target is a signal rather than silence; the local TSDB needs no external database |
| Grafana 11.2.0 | Visualization + alerting | Dashboards and alert rules both provision from files, so the repo is the source of truth |
| Docker Compose v2.29.7 | Stack orchestration | Two pinned images, two named volumes, one file — and Docker's internal DNS lets Grafana address Prometheus by container name |
| CloudWatch + SNS | Monitor the monitor | CloudWatch collects EC2 metrics at the hypervisor level, so it still sees the host when the host cannot report on itself |

---

## Security Decisions

| What I did | What it prevents |
|---|---|
| **Zero inbound SSH on either instance** — no port 22 rule, no key pair created | Eliminates the single most-attacked port on the internet. There is no credential to rotate because there is no credential |
| Grafana and Prometheus restricted to a single `/32` source | Prometheus has **no authentication whatsoever** — anyone who reaches :9090 can enumerate your infrastructure. The security group is the only control, so it has to be a single address, not a `/24` |
| Target's port 9100 rule sources from the monitor's **security group ID**, not an IP | Survives instance replacement and IP changes. Using a public IP would also route metrics out through the internet gateway and back for no reason |
| Terraform **never receives a secret** | `sensitive = true` only masks console output — the value is written to `terraform.tfstate` as plaintext JSON, and people commit that file constantly |
| Parameter Store policy scoped to `parameter/skyhigh/monitoring/*` with a separate `kms:Decrypt` on the SSM key only | The instance role can read its own three parameters and nothing else in the account |
| Instance role has **no `ssm:PutParameter`** | Discovered when password rotation failed from the instance with an AccessDenied. That is the policy working: the workload reads its credentials, a separate administrative identity writes them |
| `http_tokens = "required"` (IMDSv2) on both instances | IMDSv1 is the SSRF-to-credential-theft path behind the Capital One breach |
| `http_put_response_hop_limit = 1` | A container gets an extra network hop, so processes inside Docker cannot reach the instance metadata service. A compromised Grafana container cannot steal the instance's IAM credentials |
| node_exporter runs as a `--system` user with `/usr/sbin/nologin` and no home directory | Compromising the exporter yields a user that cannot log in and owns nothing |
| Binary owned `root:root`, mode 755 | A non-root-owned binary that systemd executes on every boot is a persistence mechanism |
| systemd `ProtectSystem`, `ProtectHome=true`, `PrivateTmp=true`, `NoNewPrivileges=true` | Least privilege applies to processes on a host, not just IAM. The exporter only reads `/proc` and `/sys`, so it needs nothing else |
| SHA256 checksum verified before installing node_exporter | You are granting a downloaded binary permanent boot-time execution on a production host |
| Grafana password read from `.env` (mode 600, gitignored); `.env.example` committed with a placeholder | The compose file references `${GF_SECURITY_ADMIN_PASSWORD}`, so the repo is publishable as-is |
| `GF_AUTH_ANONYMOUS_ENABLED=false`, `GF_USERS_ALLOW_SIGN_UP=false` | Closes anonymous read and self-registration on an internet-facing login page |
| Pinned image tags (`prom/prometheus:v2.54.1`, `grafana/grafana:11.2.0`), never `:latest` | `docker compose pull` next month would otherwise hand you a different Grafana and possibly break your dashboards |
| `:ro` on all config bind mounts | The containers read those files; nothing needs write access |
| Explicit `--storage.tsdb.retention.time=15d` | Unbounded TSDB growth filling a disk is a genuine outage cause, and the flag makes the value reviewable rather than implicit |
| Pre-push credential sweep (`git ls-files`, grep across all revs, check for `/32` leakage) | Git history is permanent and bots scrape GitHub's public event stream in real time |
| **Chose a webhook over SES SMTP** | SES SMTP requires a long-lived IAM user credential — strictly weaker than the instance-role model used everywhere else. The IAM user was deleted during the security sweep |

---

## Deployment Steps

### 1. Store the secret

```bash
read -s "PW?Grafana admin password: "
aws ssm put-parameter --name "/skyhigh/monitoring/grafana-admin-password" \
  --value "$PW" --type SecureString --region us-east-1
unset PW

# Verify the KMS round-trip works
aws ssm get-parameter --name "/skyhigh/monitoring/grafana-admin-password" \
  --with-decryption --query 'Parameter.Value' --output text | wc -c
```

### 2. Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

curl -s https://checkip.amazonaws.com    # your public IP — append /32 in tfvars

terraform init
terraform fmt && terraform validate
terraform plan
# EXPECTED: Plan: 11 to add, 0 to change, 0 to destroy.
terraform apply
```

Confirm the SNS subscription email that arrives — until you click it, the CloudWatch alarm notifies nobody.

```bash
# EXPECTED: both instances Online (allow 3 minutes for SSM agent registration)
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{ID:InstanceId,Ping:PingStatus}' --output table
```

That single command proves the IAM role attached, the outbound path works, and the subnet routes to an internet gateway — three things that would otherwise fail separately and confusingly later.

### 3. Install node_exporter on the target

```bash
aws ssm start-session --target $(terraform output -raw target_instance_id)
sudo su - ec2-user

cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/sha256sums.txt
sha256sum -c sha256sums.txt --ignore-missing
# EXPECTED: node_exporter-1.8.2.linux-amd64.tar.gz: OK — do not proceed otherwise

tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/node_exporter
sudo chmod 755 /usr/local/bin/node_exporter

sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
sudo cp /path/to/target/node_exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# Verify — the USER column must read node_exporter, not root
ps aux | grep [n]ode_exporter
curl -s http://localhost:9100/metrics | wc -l
# EXPECTED: 2000+
```

### 4. Deploy the stack on the monitor

```bash
aws ssm start-session --target $(terraform output -raw monitor_instance_id)
sudo su - ec2-user

sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
newgrp docker

# Compose v2 as a CLI plugin — this is what makes `docker compose` (space) work
DOCKER_CONFIG=/usr/local/lib/docker
sudo mkdir -p $DOCKER_CONFIG/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o $DOCKER_CONFIG/cli-plugins/docker-compose
sudo chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

git clone <this-repo> ~/skyhigh-p5
cp -r ~/skyhigh-p5/stack ~/monitoring
cd ~/monitoring

# Set the target's PRIVATE IP in prometheus/prometheus.yml

# Pull the secret with the instance role — nothing is stored on this host
GF_PW=$(aws ssm get-parameter --name "/skyhigh/monitoring/grafana-admin-password" \
  --with-decryption --query 'Parameter.Value' --output text --region us-east-1)
echo "GF_SECURITY_ADMIN_PASSWORD=$GF_PW" > .env
chmod 600 .env
unset GF_PW

docker compose up -d
```

### 5. Verify the full pipeline

```bash
curl -s http://localhost:9090/-/healthy
# EXPECTED: Prometheus Server is Healthy.

curl -s http://localhost:3000/api/health
# EXPECTED: {"database": "ok", ...}

curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[^"]*"'
# EXPECTED: two results, both "up"
```

Then open `http://<monitor-public-ip>:3000`. The Prometheus datasource and the SkyHigh dashboard will already exist — nobody clicked them into being.

### 6. Prove the provisioning actually works

```bash
docker compose down
docker volume rm monitoring_grafana-data     # destroys Grafana's entire database
docker compose up -d
```

Log back in. If the dashboard is there, it came from the files in this repo. If it isn't, your provisioning was never real and you would have shipped a repo that cannot rebuild itself.

### 7. Trigger an alert on purpose

```bash
# On the target
sudo dnf install -y stress-ng
stress-ng --cpu 4 --timeout 600s --metrics-brief
```

Watch the rule go Normal → Pending → Firing over roughly four minutes, then the webhook arrive. **Use 600 seconds, not the 180 the assignment suggests** — see Challenges #6.

---

## Runbooks

Every alert this stack can fire has a runbook: what it means, what to check first, ranked causes, and what to capture before escalating.

| Alert | Severity | Source | Runbook |
|---|---|---|---|
| High CPU Usage | warning | Grafana | [docs/runbooks/high-cpu-usage.md](docs/runbooks/high-cpu-usage.md) |
| Low Disk Space | critical | Grafana | [docs/runbooks/low-disk-space.md](docs/runbooks/low-disk-space.md) |
| Target Down | critical | Prometheus | [docs/runbooks/target-down.md](docs/runbooks/target-down.md) |
| Monitoring Stack Down | critical | CloudWatch | [docs/runbooks/monitoring-stack-down.md](docs/runbooks/monitoring-stack-down.md) |

Index: [docs/runbooks/README.md](docs/runbooks/README.md)

---

## Challenges and Solutions

**1. `sensitive = true` does not protect a secret in Terraform**

- **Problem:** The obvious design is a `sensitive` variable for the Grafana password.
- **Root cause:** `sensitive = true` does exactly one thing — it replaces the value with `(sensitive value)` in plan and apply output. The value is still written to `terraform.tfstate` as plaintext JSON, along with `terraform.tfstate.backup` and any saved plan file.
- **Solution:** Terraform never receives the secret. It creates the *IAM permission* to read a Parameter Store path; the value is written by hand with `read -s` and pulled at runtime by the instance role. No secret in state, no secret in git, no secret in shell history.

**2. The instance role could not rotate its own password — and that was correct**

- **Problem:** `aws ssm put-parameter --overwrite` from the monitor failed with AccessDenied on `ssm:PutParameter`.
- **Root cause:** The CLI on an EC2 instance uses the instance role, which has `GetParameter`, `GetParameters`, `GetParametersByPath`, and `kms:Decrypt` — and deliberately no write permission.
- **Solution:** Rotate from an administrative identity, pull from the instance. This is the correct separation and the failure was the policy proving itself. A workload that can rewrite its own credentials is a workload that can be used to rewrite them.

**3. Heredocs mangled repeatedly through the SSM terminal**

- **Problem:** `sudo tee file <<'EOF'` produced a truncated systemd unit twice. The terminator merged into the final directive, producing `EOFtedBy=multi-user.target` and silently dropping the `[Install]` section and all four hardening lines.
- **Root cause:** Multi-line pastes through a Session Manager terminal are not reliable — line handling drops blank lines and folds content.
- **Solution:** Built the file one `echo | sudo tee -a` line at a time. Tedious, but each line is independent and nothing can merge. The lesson generalizes: for anything longer than a few lines, use an editor on the box or transfer the file — do not paste into a shell.

**4. Provisioned dashboards fail with "datasource DS_PROMETHEUS was not found"**

- **Problem:** A dashboard exported with "export for sharing externally" worked on import but every panel read *No data* when provisioned from a file.
- **Root cause:** The export format wraps the datasource in a `${DS_PROMETHEUS}` input variable and an `__inputs` block, which the **import wizard** resolves by asking a human to pick a datasource. Provisioning from file has no human, so the variable never binds. With only one datasource configured, Grafana skips the picker on import entirely — so the problem is invisible until you provision.
- **Solution:** Pin `uid: prometheus` in the datasource provisioning file, then rewrite the dashboard JSON to reference that fixed UID and delete the `__inputs` block. Export-for-import and provision-from-file are different workflows with incompatible assumptions about who resolves the datasource.

**5. A 300-second load test cannot fire a 2-minute alert**

- **Problem:** `stress-ng --timeout 300s` pinned CPU at 99% and the alert went Pending — then back to Normal without ever firing.
- **Root cause:** `rate(node_cpu_seconds_total[5m])` averages over a five-minute window, so the metric lags actual load by 60–90 seconds on the way up. Add a 1-minute rule evaluation interval and a 2-minute pending period, and the alert needs roughly four minutes of *sustained* load to fire. The assignment's suggested 180 seconds is not close.
- **Solution:** 600 seconds. The state history made the diagnosis trivial — Pending at A=99.18, Normal at A=64.39, no Firing row in between. The window that smooths out false alarms is the same window that delays real ones; that tradeoff is a design decision, not a bug.

**6. Grafana 11 broke dashboard 1860's template variables**

- **Problem:** Every panel of the imported community dashboard showed *No data* with empty `nodename` and `instance` dropdowns, even though the metrics were confirmed present in Prometheus.
- **Root cause:** Grafana 11 requires an explicit **Query type** on variables where older versions inferred it. Dashboard 1860's JSON came across with the field unset, so every variable returned nothing — and because the variables chain (`instance` filters on `$nodename`, which filters on `$job`), one broken link emptied all of them.
- **Solution:** Rebuilt the variable queries, then abandoned 1860 entirely and wrote a five-panel dashboard by hand. Keeping it as a reference and building my own was the better outcome: I can explain every query in the dashboard I ship, and there is no inherited 16,000-line JSON to debug.

**7. A 673 KB base64 paste corrupts in a terminal**

- **Problem:** Transferring a dashboard JSON to the instance via `base64 | pbcopy` and a waiting `cat >` failed with `base64: invalid input`.
- **Root cause:** Terminal paste buffers are not a file transfer mechanism at that size. Compounding it, copying the *next* command from my notes overwrote the clipboard before I could paste — `pbpaste | wc -c` returned 15 bytes, the length of the command I had just copied.
- **Solution:** Pushed to GitHub and cloned on the instance. The repo was going to be the transport anyway; I had just reached for the terminal first because the remote didn't exist yet.

---

## Cost Notes

**~$0.03/hour while running. Under $3 for the entire project.**

| Resource | Rate | Notes |
|---|---|---|
| 2× t2.micro (us-east-1) | ~$0.0116/hr each | ~$8.35/mo each if left running 24/7 |
| 20 GB gp3 (monitor) | ~$1.60/mo | Sized for TSDB growth; charged even when stopped |
| 8 GB gp3 (target) | ~$0.64/mo | Deliberately small so the disk alert can be triggered realistically |
| CloudWatch alarm | $0.10/mo | First 10 alarms free |
| SNS email | ~$0.00 | First 1,000 notifications free |
| SSM Parameter Store (Standard) | $0.00 | Free to 10,000 parameters — Advanced tier is $0.05 each, stay on Standard |
| Session Manager | $0.00 | No charge, and no bastion host to pay for either |

**Two instances running continuously is 1,440 instance-hours per month**, which exceeds the legacy free tier's 750 across all t2.micro usage. The operating discipline was to stop both instances at the end of every session:

```bash
aws ec2 stop-instances --instance-ids <monitor-id> <target-id>
```

Stopped instances cost only their EBS (~$2.24/mo combined). Everything comes back on its own — `restart: unless-stopped` on the containers and `WantedBy=multi-user.target` on node_exporter — so a resume is `start-instances`, wait two minutes, and grab the new public IP.

**The production alternative, for comparison:** Amazon Managed Service for Prometheus plus Amazon Managed Grafana removes the instance you have to patch and monitor, at roughly $9/month per active Grafana user plus metric ingestion charges. That is the right answer for a real team and the wrong one for learning how the pieces fit.

---

## Teardown

```bash
# 1. Confirm what exists before destroying it
cd terraform
terraform plan -destroy

# 2. Destroy everything Terraform manages
terraform destroy
# Removes: 2 instances, 2 security groups, IAM role + policies + instance profile,
#          SNS topic + subscription, CloudWatch alarm

# 3. Remove the secrets — Terraform never created these, so it cannot delete them
aws ssm delete-parameter --name "/skyhigh/monitoring/grafana-admin-password" --region us-east-1
aws ssm delete-parameter --name "/skyhigh/monitoring/smtp-user" --region us-east-1
aws ssm delete-parameter --name "/skyhigh/monitoring/smtp-password" --region us-east-1

# 4. Verify nothing is left
aws ec2 describe-instances --filters "Name=tag:Project,Values=skyhigh-monitoring" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text
aws ssm get-parameters-by-path --path "/skyhigh/monitoring" --region us-east-1 \
  --query 'Parameters[].Name' --output text
# EXPECTED: both empty
```

**Security sweep findings, remediated at teardown:**

- Deleted the SES SMTP IAM user and its access key — created during an abandoned email-contact-point attempt, never used. Removing it required unwinding an access key, an attached policy, and a group membership before the user itself could be deleted. Every other resource in this project came out in one `terraform destroy`.
- Removed the stray `.env` written to the target instance during the wrong-host incident.
- Removed Docker from the target, where it was installed by mistake and never used.
- Audited git history for credentials, IP addresses, and state files before the first push.

**Recovery from nothing is `terraform apply` plus one parameter write.** Everything else — the compose file, the scrape config, the alert rules, the dashboard JSON, the systemd unit — is in this repository.

---

## Project Structure

```
Monitor-w-Prom-Graf/
├── terraform/
│   ├── versions.tf                    # provider pinned ~> 5.0, default_tags
│   ├── variables.tf                   # region, my_ip (CIDR-validated), alert_email
│   ├── data.tf                        # default VPC, latest AL2023 AMI (owners = amazon)
│   ├── network.tf                     # 2 SGs — target's 9100 sources from monitor's SG ID
│   ├── iam.tf                         # role, SSM core, path-scoped Parameter Store + kms:Decrypt
│   ├── ec2.tf                         # both instances: IMDSv2 required, encrypted EBS, no key pair
│   ├── cloudwatch.tf                  # SNS topic + email sub + monitor-the-monitor alarm
│   ├── outputs.tf                     # instance IDs, monitor public IP, target PRIVATE IP
│   └── terraform.tfvars.example       # template; the real tfvars is gitignored
├── stack/                             # deployed to skyhigh-monitor
│   ├── docker-compose.yml             # pinned images, named volumes, :ro config mounts
│   ├── .env.example                   # placeholder — the real .env is mode 600 and gitignored
│   ├── prometheus/
│   │   ├── prometheus.yml             # 15s scrape, static target on the PRIVATE ip
│   │   └── rules/node_alerts.yml      # TargetDown (up == 0), HighCPUUsage, LowDiskSpace
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/prometheus.yml   # uid: prometheus — the fix for provisioned dashboards
│       │   └── dashboards/
│       │       ├── dashboards.yml            # file provider, disableDeletion
│       │       └── skyhigh-production-monitoring.json   # THE DELIVERABLE — 5 hand-written panels
│       └── reference/
│           └── node-exporter-full.json       # community dashboard 1860, kept for reference only
├── target/
│   └── node_exporter.service          # systemd unit — non-root user, restart, filesystem hardening
├── docs/
│   └── runbooks/                      # one per alert, plus an index
├── .gitignore                         # *.tfvars, *.tfstate, .env, *.pem — written before git init
└── README.md
```

---

## Alerting Summary

| Alert | Threshold | Pending | Fires via | Rationale |
|---|---|---|---|---|
| High CPU Usage | > 80% | 2m | Grafana → webhook | CPU spikes from deploys and cron jobs self-resolve; two minutes filters them out |
| Low Disk Space | > 90% | 0s | Grafana → webhook | A full disk does not drain itself — waiting adds delay and nothing else |
| TargetDown | `up == 0` | 1m | Prometheus | The dead-man's switch. A host that stopped reporting is not a healthy host |
| HighCPUUsage | > 80% | 2m | Prometheus | Same condition as the Grafana rule, evaluated independently so it survives Grafana being down |
| LowDiskSpace | > 90% | 5m | Prometheus | Independent duplicate of the Grafana disk rule |
| Monitor CPU High | > 90% | 5m (1 period) | CloudWatch → SNS email | Watches the monitoring host from outside it, on a notification path that shares nothing with Grafana |

`treat_missing_data = "breaching"` on the CloudWatch alarm: if metrics stop arriving, that is treated as a breach rather than ignored. The default (`missing`) stays silent, which is the wrong default for a safety net.

---

## Future Improvements

1. **EC2 service discovery instead of static scrape targets** — `ec2_sd_config` with tag-based discovery finds instances automatically. Today a replaced instance means hand-editing `prometheus.yml`, which is a known failure mode documented in the Target Down runbook.
2. **Alertmanager** — the Prometheus-native rules currently fire into nothing. Alertmanager adds grouping, inhibition, silencing, and routing, and would stop a single incident from producing five separate notifications.
3. **Deploy the stack with Terraform `user_data` or an SSM document** — the compose files are copied to the instance by hand today. Full IaC would close the drift gap between the repo and the running host.
4. **Alert on `StatusCheckFailed`, not just CPU** — the CloudWatch alarm catches a pegged monitor but not a hung one. This is the known gap named explicitly in the monitoring-stack-down runbook.
5. **An external uptime check against Grafana's health endpoint** — CloudWatch sees the instance, not the application. A Prometheus process that is alive but failing every scrape triggers nothing today.
6. **TLS and authentication in front of Prometheus** — a `/32` source rule is a single control on an unauthenticated service, and residential IPs rotate. A reverse proxy with auth would let the SG rule become a second layer rather than the only one.
7. **Remote write to Amazon Managed Prometheus** — local TSDB dies with the instance. Remote write makes metrics survive host loss and removes the retention-versus-disk-size tradeoff.
8. **Provision Grafana alert rules from file** — the dashboard and datasource are code; the alert rules are still clicked in. `provisioning/alerting/` closes that gap and makes the alert definitions reviewable in a pull request.
9. **A second Prometheus scraping the first** — the cheapest real answer to "who watches the watchmen," and it would cover the failure mode the CloudWatch CPU alarm misses.
10. **Recording rules for the expensive queries** — `rate(node_cpu_seconds_total[5m])` is computed on every dashboard refresh and every rule evaluation. Precomputing it costs storage and saves query time at scale.