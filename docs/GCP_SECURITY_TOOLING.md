# GCP Security Tooling Configuration & Validation

This document implements the **GCP Security Tooling Configuration & Validation** ticket: enable GCP-native security tools, configure preventative and detective controls, review findings for intentional misconfigurations, and document security posture.

## Overview

- **Cloud Audit Logs**: Admin Activity (always on), Data Access for Storage and Compute, enabled via Terraform.
- **Security Command Center (SCC)**: Standard tier; enable in Console and review findings.
- **Preventative control**: Organization Policy “Require OS Login” (Terraform).
- **Detective controls**: Cloud Monitoring alerts for firewall changes and storage bucket IAM changes (Terraform).
- **Validation**: Test alerts, query audit logs, document what was detected vs. missed.

---

## 1. Deploy Security Configuration with Terraform

**Required IAM**: The principal running `terraform apply` (e.g. automation service account or your user) needs:

- `roles/monitoring.alertPolicyEditor` and `roles/monitoring.notificationChannelEditor` for alert policies (included in `scripts/gcp-bootstrap.sh`; if you bootstrapped earlier, grant these and re-run apply).
- For **Require OS Login** org policy: `roles/orgpolicy.policyAdmin` is an **organization-level** role and cannot be granted on a project. If Terraform fails with 403, set `enable_require_os_login = false` and enforce the policy in Console: **IAM & Admin → Organization policies** (filter by “OS Login”), or use the direct link in the doc below.

After infrastructure and application are deployed, apply the security tooling Terraform resources:

```bash
cd terraform
terraform init   # if not already
terraform plan  # review: audit configs, org policy, logging metrics, alert policies
terraform apply
```

This creates:

- **Audit configs** (`audit_logs.tf`): Data Access + Admin Read for `storage.googleapis.com` and `compute.googleapis.com`. Admin Activity is always on at the project level.
- **Org policy** (`org_policy.tf`): `constraints/compute.requireOsLogin` enforced when `enable_require_os_login` is true. Default is off for lab projects (no orgpolicy.policyAdmin); enable manually in Console or set the variable to true when org permissions exist. Use **IAP tunnel** or OS Login for SSH (e.g. `gcloud compute ssh INSTANCE --zone=ZONE --tunnel-through-iap`).
- **Log-based metrics** (`monitoring_alerts.tf`): `wiz_exercise_firewall_change`, `wiz_exercise_storage_bucket_iam_change`.
- **Alert policies**: “[Wiz Exercise] Firewall rule create/update/delete” and “[Wiz Exercise] Storage bucket IAM change”. Optional: set `alert_notification_email` in `terraform.tfvars` to create an email notification channel.

Optional email for alerts (in `terraform.tfvars`):

```hcl
alert_notification_email = "your-email@example.com"
```

### Require OS Login via Console (when Terraform cannot set org policy)

`roles/orgpolicy.policyAdmin` is organization-level only. To enforce **Require OS Login** without it:

1. Open **IAM & Admin → Organization policies**:  
   [https://console.cloud.google.com/iam-admin/orgpolicies?project=YOUR_PROJECT_ID](https://console.cloud.google.com/iam-admin/orgpolicies?project=YOUR_PROJECT_ID) (replace `YOUR_PROJECT_ID`).
2. Find **Compute Engine → Require OS Login** (or filter by “OS Login”).
3. Click **Manage policy** → **Override** (or **Edit**) → set to **Enforced** → **Set policy**.

SSH via `gcloud compute ssh INSTANCE --zone=ZONE --tunnel-through-iap` continues to work.

---

## 2. Enable Security Command Center (Standard)

1. Ensure the API is enabled and follow Console steps:

   ```bash
   export GCP_PROJECT_ID=your-project-id
   ./scripts/enable-scc-standard.sh
   ```

2. In Console, open [Security Command Center](https://console.cloud.google.com/security/command-center) for your project, activate **Standard** tier, and enable:
   - **Security Health Analytics**
   - **Web Security Scanner** (if available)

3. Wait for the initial scan to complete (minutes to hours). Then use **Findings** to review results.

---

## 3. Review SCC Findings (Intentional Misconfigurations)

In **Security Command Center → Findings**, filter by severity and check whether each intentional misconfiguration is reported:

| Misconfiguration | Expected (exercise) | SCC often detects | Notes |
|------------------|---------------------|--------------------|--------|
| Public SSH access on VM (firewall 0.0.0.0/0:22) | Yes | Yes (e.g. “Open firewall”) | Security Health Analytics |
| Public Cloud Storage bucket | Yes | Yes (e.g. “Public bucket”) | Security Health Analytics |
| Outdated OS version on VM | Yes | Maybe | “Outdated image” / CVE findings |
| Excessive IAM permissions (VM SA with compute.admin) | Yes | Yes (e.g. “Overprivileged”) | Security Health Analytics |
| Kubernetes pod with cluster-admin | Yes | Yes (e.g. “Privileged workload”) | If detector supports GKE RBAC |

Document for each: **Detected** / **Not detected** and which finding ID or title. Capture screenshots for presentation.

---

## 4. Test Detective Controls (Alerts)

- **Firewall change**: Create or update a firewall rule (e.g. duplicate rule or add a tag). Within a few minutes, check **Monitoring → Alerting → Incidents** for “[Wiz Exercise] Firewall rule create/update/delete”. If you set `alert_notification_email`, check email.
- **Bucket IAM change**: Run a no-op or real `gsutil iam set` (or Terraform change) on the backup bucket’s IAM. Check for “[Wiz Exercise] Storage bucket IAM change” incident.

If alerts do not fire, confirm in **Logging → Logs Explorer** that audit logs for `compute.googleapis.com` (firewalls) and `storage.googleapis.com` (setIamPolicy) are present. Log-based metrics can take a short time to populate.

**Quick test**: A firewall rule update was run (e.g. `gcloud compute firewall-rules update wiz-exercise-allow-ssh-vm --description=...`). Check incidents: [Monitoring → Incidents](https://console.cloud.google.com/monitoring/alerting/incidents?project=wizdemo-487311) (replace project if different). You should see an incident for “[Wiz Exercise] Firewall rule create/update/delete” within a few minutes.

---

## 5. Query Audit Logs and Export Samples

In **Logging → Logs Explorer**, use the following (replace `PROJECT_ID` if needed).

**VM creation (Compute):**

```text
protoPayload.serviceName="compute.googleapis.com"
protoPayload.methodName=~"v1.compute.instances.insert"
```

**Firewall change:**

```text
protoPayload.serviceName="compute.googleapis.com"
(protoPayload.methodName="v1.compute.firewalls.insert" OR
 protoPayload.methodName="v1.compute.firewalls.patch" OR
 protoPayload.methodName="v1.compute.firewalls.delete")
```

**Storage bucket / object access (Data Access):**

```text
protoPayload.serviceName="storage.googleapis.com"
```

**Export for presentation:** In Logs Explorer, use “Export” or “Save as” to export a small sample (e.g. last 1 hour) to a file or sink.

A helper script to list recent audit log entries (conceptually) can be:

```bash
# Example: list recent firewall-related audit entries (run from repo root)
gcloud logging read '
  protoPayload.serviceName="compute.googleapis.com"
  (protoPayload.methodName=~"firewalls.(insert|patch|delete)")
' --project=PROJECT_ID --limit=20 --format=json
```

Use your `PROJECT_ID` and adjust filters as needed.

---

## 6. Security Posture Documentation (Template)

Use this template to document what was detected, what wasn’t, and why it matters.

### 6.1 Summary of detected misconfigurations

- List each intentional misconfiguration that **was** detected by SCC or other tools (e.g. “Public bucket”, “Open SSH firewall”, “Overprivileged VM SA”, “Cluster-admin pod”).
- For each: which tool (SCC Security Health Analytics, SCC Web Scanner, custom alert) and finding name/ID.

### 6.2 Which tools detected which issues

- **SCC**: List findings by category (network, IAM, storage, GKE).
- **Cloud Monitoring alerts**: Firewall change, bucket IAM change (and any others you add).
- **Audit logs**: Used for detection of who did what and when (e.g. firewall/bucket changes).

### 6.3 Misconfigurations NOT detected (and why)

- List any intentional weaknesses that **no** tool flagged (e.g. “Outdated OS” if no CVE/outdated-image finding).
- Short reason (e.g. “No detector for EOL image in this tier”, “GKE RBAC not in scope for Standard”).

### 6.4 Preventative vs. detective controls

- **Preventative**: Require OS Login (Org Policy) — blocks project-wide SSH keys; SSH via IAP/OS Login still works.
- **Detective**: SCC findings, Cloud Monitoring alerts on firewall and bucket IAM. Alerts do not prevent the change but surface it quickly.

### 6.5 Risk reduction talking points

- Audit logs support incident response and compliance (who changed what and when).
- SCC Standard increases visibility into public exposure, overprivileged identities, and some GKE/config issues.
- Alerts on firewall and bucket IAM help catch accidental or malicious changes soon after they occur.
- Require OS Login reduces key sprawl and enforces a single path (IAP/OS Login) for VM access.

---

## 7. Screenshots Checklist

Capture for presentation:

- [ ] **Audit Logs**: IAM & Audit → Audit Logs (or Logging) showing Data Access / Admin Activity for Compute and Storage.
- [ ] **SCC Overview**: Security Command Center dashboard with Standard tier and detectors enabled.
- [ ] **SCC Findings**: List/filter view and at least one finding (e.g. public bucket or open firewall).
- [ ] **Org Policy**: Resource Manager → Org policies → `compute.requireOsLogin` enforced.
- [ ] **Alert policies**: Monitoring → Alerting → policies “[Wiz Exercise] Firewall…” and “…Storage bucket IAM…”.
- [ ] **Incident**: One incident from triggering a firewall or bucket IAM change.
- [ ] **Logs Explorer**: Sample audit log entries (e.g. firewall or bucket method names).

---

## 8. Validation Checklist (Flow 6)

- [ ] Cloud Audit Logs enabled (Admin Activity, Data Access for Storage/Compute).
- [ ] Security Command Center Standard tier active; Security Health Analytics (and Web Security Scanner if available) enabled.
- [ ] SCC findings reviewed and documented (public SSH, public bucket, outdated OS, excessive IAM, cluster-admin pod).
- [ ] At least one Organization Policy implemented (Require OS Login) and enforced without breaking IAP/OS Login access.
- [ ] At least one Cloud Monitoring alert configured and tested (firewall change and/or bucket IAM change).
- [ ] Audit logs queried and sample exported.
- [ ] Security posture documented (detected, not detected, preventative vs. detective, talking points).
- [ ] Screenshots captured for all of the above.

---

## Related

- [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md) – CI/CD and security gating.
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) – APIs and service account (includes `securitycenter.googleapis.com`).
- [APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md) – Tasky and intentional cluster-admin SA.
