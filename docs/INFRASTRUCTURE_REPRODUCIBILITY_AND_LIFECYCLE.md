# Infrastructure Reproducibility & Lifecycle Validation

This document describes how to validate that the Wiz Technical Exercise V4 infrastructure is **reproducible** and that its **lifecycle** (init → plan → apply, and optional destroy → apply) is consistent and drift-free. It supports the **Infrastructure Reproducibility & Lifecycle Validation** ticket.

## Goals

- **Lifecycle validation**: After a successful `terraform apply`, running `terraform plan` should show **no changes** (no drift between state and actual resources).
- **Reproducibility**: The same Terraform code and configuration can be used to recreate the full stack from scratch (e.g. after a controlled `terraform destroy`, or in a new project with bootstrap and tfvars).

## Prerequisites

- [Flow 1](VALIDATION_FLOW1.md) complete: GCP project, APIs, service account, **Terraform state GCS bucket** (with versioning).
- **Terraform** >= 1.5.0 and **gcloud** CLI.
- **Backend**: State stored in GCS (e.g. `PROJECT_ID-tfstate-wiz-exercise`, prefix `terraform/state`).
- **Variables**: `terraform/terraform.tfvars` with at least `project_id`, `mongodb_admin_password`, and `mongodb_app_password`. See [INFRASTRUCTURE_DEPLOYMENT.md](INFRASTRUCTURE_DEPLOYMENT.md) and `terraform/terraform.tfvars.example`.

## Standard Lifecycle

1. **Init** (with backend)
   ```bash
   cd terraform
   terraform init \
     -backend-config="bucket=${GCP_PROJECT_ID}-tfstate-wiz-exercise" \
     -backend-config="prefix=terraform/state"
   ```
2. **Plan**
   ```bash
   terraform plan -out=tfplan
   ```
3. **Apply**
   ```bash
   terraform apply tfplan
   ```

Or use the helper script from repo root (sets backend from `GCP_PROJECT_ID`):

```bash
export GCP_PROJECT_ID="wizdemo-487311"
./scripts/terraform-deploy.sh
```

## Lifecycle Validation (No Drift)

After every apply, confirm that the deployed infrastructure matches the code and state:

```bash
cd terraform
terraform plan -detailed-exitcode
```

- **Exit 0**: No changes (desired).
- **Exit 2**: Plan has changes (drift or code/tfvars change).
- **Exit 1**: Plan error (e.g. missing variables). If you see "Error acquiring the state lock", another Terraform run is holding the lock—wait for it to finish or run `terraform force-unlock LOCK_ID` if the other process is gone.

To automate this, use the validation script (from repo root):

```bash
export GCP_PROJECT_ID="wizdemo-487311"
./scripts/validate-terraform-lifecycle.sh plan
```

The script runs `terraform init` (with backend) and `terraform plan -detailed-exitcode`. It exits 0 only when the plan is empty (no drift).

## Post-Apply Validation (App, MongoDB, Misconfigs)

The **validate** command requires **kubectl** and **gcloud** (and GKE auth plugin). It reads Terraform outputs from state, so run it from an environment where `terraform output` can read the same backend (e.g. after a successful apply). If `mongodb_connection_string` is not in state or not available (e.g. tfvars not loaded), the MongoDB ping check is skipped.

After apply (and after Tasky is deployed and Ingress has an external IP), run the **validate** command to check:

- **App**: HTTP 200 on `/`, and a CRUD path (e.g. GET `/todos/1`) returns 200/404/401.
- **MongoDB**: A one-off pod runs `mongosh` with `mongodb_connection_string` and pings the database.
- **Intentional misconfigs**: Backup bucket IAM includes `allUsers` (public read/list); SSH firewall allows `0.0.0.0/0`.

From repo root:

```bash
export GCP_PROJECT_ID="wizdemo-487311"
./scripts/validate-terraform-lifecycle.sh validate
```

The script prints a **summary table** of each check and **exits non-zero** if any check fails. Interpret results:

| Result | Meaning |
|--------|--------|
| **PASS** | Check succeeded (for app/Mongo: service is reachable; for misconfigs: intentional state is present). |
| **PASS (expected)** | Intentional misconfiguration is present as required (e.g. public bucket, SSH open). |
| **FAIL** | Check failed (e.g. app not 200, Mongo not reachable, or a misconfig missing). Fix the cause and re-run. |
| **SKIP** | Check was skipped (e.g. no Terraform output or optional path not deployed). |

If Tasky is not deployed (`tasky_enabled = false`), Ingress IP and App checks will fail; MongoDB ping still runs from the cluster if the connection string is available. Resolve failures before considering the lifecycle validated.

**If MongoDB ping fails (ECONNREFUSED):** The MongoDB VM may not have finished its startup script or the service may not be running. The startup script (in `terraform/scripts/mongodb-startup.sh.tpl`) installs MongoDB, enables auth, and binds to `0.0.0.0` so GKE pods can connect. After changing that script, run `terraform apply` then **reboot the VM** so the updated startup runs:  
`gcloud compute instances reset MONGODB_VM_NAME --zone=ZONE --project=PROJECT_ID`  
(or recreate the VM: `terraform taint google_compute_instance.mongodb` then `terraform apply`).

**If SSH firewall check fails:** The validate script uses the firewall name from Terraform output `ssh_firewall_name`. Ensure the rule exists and allows `0.0.0.0/0` (e.g. run `terraform apply` so the rule is present).

For more failure scenarios and recovery (state lock, CI gates, deployment, Argo CD), see [ERROR_TESTING_AND_RECOVERY_PROCEDURES.md](ERROR_TESTING_AND_RECOVERY_PROCEDURES.md).

## Reproducibility (Destroy and Re-Apply)

To prove the stack can be recreated from the same code and config:

1. **Ensure you have**:
   - The same `terraform.tfvars` (or equivalent env/CLI vars) and any required secrets (MongoDB passwords, etc.).
   - The state bucket and backend config so Terraform can run again after destroy (the bucket itself is **not** managed by this Terraform config; it is created by the bootstrap script).

2. **Destroy** (removes all managed resources: VPC, GKE, VM, bucket, firewalls, etc.):
   ```bash
   cd terraform
   terraform destroy
   ```
   Review the plan and confirm. The state file in GCS will be updated (resources removed from state); the state bucket is left intact.

3. **Re-apply** (recreate everything):
   ```bash
   terraform init -reconfigure \
     -backend-config="bucket=${GCP_PROJECT_ID}-tfstate-wiz-exercise" \
     -backend-config="prefix=terraform/state"
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

Optional: use the validation script in reproduce mode (destructive; requires confirmation):

```bash
export GCP_PROJECT_ID="wizdemo-487311"
REPRODUCE=1 ./scripts/validate-terraform-lifecycle.sh reproduce
```

This runs destroy then apply; use only in a non-production or lab project.

### Argo CD mode (argocd_enabled)

When using Argo CD (`argocd_enabled=true`, `tasky_enabled=false`), the recreate flow works as follows:

- **Cloud NAT** (`terraform/network.tf`): Created as part of the standard apply (no `-target`). Private GKE nodes need NAT to pull images from quay.io (Argo CD) and Artifact Registry (Tasky). Without NAT, Argo CD pods will be in `ImagePullBackOff`.
- **Creation order**: VPC → subnets → router → NAT → GKE → Argo CD install → Application. Terraform resolves dependencies; no manual ordering is needed.
- **Argo CD install**: Uses `--server-side --force-conflicts` to avoid ApplicationSet CRD size limits. See `terraform/argocd.tf`.

Ensure `argocd_git_repo_url` and `argocd_git_revision` are set in `terraform.tfvars` before apply.

## What Is Not Recreated by Terraform

- **Terraform state GCS bucket**: Created by `scripts/gcp-bootstrap.sh` (or equivalent). If you destroy the project or delete the bucket, you must run bootstrap again to create the bucket before running Terraform.
- **Service account and IAM**: The bootstrap script creates the automation SA and state bucket; Terraform uses that SA. Destroy does not remove the SA or bucket.
- **Data inside resources**: Destroy deletes the MongoDB VM (and any data on it), the backup bucket and its objects, and the GKE cluster and any workloads. Re-apply creates empty resources; MongoDB will be reinstalled by the VM startup script on first boot.

**Destroy limitations (may leave a few resources):** If the automation service account does not have `iam.serviceAccounts.delete`, Terraform will not be able to delete the two managed service accounts (GKE node SA, MongoDB VM SA); remove them manually in the console or grant the permission. The backup bucket cannot be destroyed if it contains objects unless `force_destroy = true` is set on the bucket resource (in `backup_bucket.tf`); empty the bucket first or set `force_destroy` for a full destroy.

## Cost Control and Orphan Check

### Expected running costs

With the full stack applied (VPC, GKE, MongoDB VM, backup bucket, Artifact Registry, optional Tasky), you incur:

- **GKE**: Cluster + node pool (e.g. e2-medium nodes); main cost driver.
- **GCE**: One VM for MongoDB (e2-medium or similar).
- **Cloud Storage**: Backup bucket and Terraform state bucket (small unless you store large backups).
- **Artifact Registry**: Storage for container images.
- **Reserved IPs**: Ingress load balancer (when Tasky is deployed).

Use the [GCP Pricing Calculator](https://cloud.google.com/products/calculator) or the Billing console for your project to estimate. Lab projects (e.g. CloudLabs) may have credits or limits.

### Teardown steps

To stop billing for Terraform-managed resources:

1. **Destroy Terraform-managed resources**  
   From `terraform/`: run `terraform destroy` and confirm. This removes GKE cluster, VM, backup bucket, Artifact Registry repo, firewalls, Cloud NAT and router, VPC (and Tasky or Argo CD if deployed). The state file in GCS is updated; the **state bucket itself is not deleted** by Terraform.

2. **Optional: remove the state bucket**  
   If you are decommissioning the project entirely, delete the state bucket (e.g. `gsutil -m rm -r gs://PROJECT_ID-tfstate-wiz-exercise`) after destroy. Ensure no other automation uses it.

3. **Optional: delete the project**  
   For lab or one-off use, you can delete the entire GCP project to ensure no leftover resources (after destroying Terraform resources and optionally the state bucket).

### When to run the orphan check

Run **after** `terraform destroy` to confirm no billable resources are left behind (e.g. a failed destroy, manually created resources, or resources in a different region):

```bash
export GCP_PROJECT_ID="your-project-id"
./scripts/check-orphaned-resources.sh
```

The script lists GKE clusters, GCE instances, disks, reserved IPs, GCS buckets (excluding the Terraform state bucket), and Artifact Registry repositories. It **exits non-zero** if any of these exist, so you can use it in runbooks or CI to fail when orphans are detected.

### How to interpret and resolve findings

| Resource type   | Meaning if present | How to resolve |
|-----------------|--------------------|----------------|
| GKE clusters    | A cluster still exists. | `gcloud container clusters delete CLUSTER_NAME --region=REGION --project=PROJECT_ID` (or re-run destroy if it was missed). |
| GCE instances   | A VM still exists. | `gcloud compute instances delete INSTANCE_NAME --zone=ZONE --project=PROJECT_ID` or fix Terraform state and run destroy again. |
| Disks          | Unattached or leftover disks. | `gcloud compute disks delete DISK_NAME --zone=ZONE --project=PROJECT_ID` (or region for regional disks). |
| Reserved IPs   | Addresses not released (e.g. LB). | `gcloud compute addresses delete NAME --region=REGION --project=PROJECT_ID` (or `--global` for global addresses). |
| GCS buckets    | Buckets other than the state bucket. | Delete if not needed: `gsutil rm -r gs://BUCKET_NAME`. The state bucket (`*tfstate-wiz-exercise`) is excluded by the script and is expected after destroy. |
| Artifact Registry | A repository still exists. | `gcloud artifacts repositories delete REPO_ID --location=LOCATION --project=PROJECT_ID` or run Terraform destroy again. |

Resolve each listed resource (delete or re-run destroy as appropriate), then run `./scripts/check-orphaned-resources.sh` again until it exits 0.

## Quick Reference

| Action              | Command / Script |
|---------------------|------------------|
| Deploy              | `./scripts/terraform-deploy.sh` |
| Validate no drift   | `./scripts/validate-terraform-lifecycle.sh plan` |
| Post-apply checks   | `./scripts/validate-terraform-lifecycle.sh validate` (app, Mongo, misconfigs; summary table; non-zero on failure) |
| Destroy             | `cd terraform && terraform destroy` |
| Reproduce (destroy + apply) | `REPRODUCE=1 ./scripts/validate-terraform-lifecycle.sh reproduce` |
| Orphan check (after destroy) | `./scripts/check-orphaned-resources.sh` (exit non-zero if billable resources remain) |

## Related

- [VALIDATION_FLOW2.md](VALIDATION_FLOW2.md) – Infrastructure deployment acceptance criteria (including “terraform plan shows no changes after apply”).
- [FLOW2_VERIFICATION_CHECKLIST.md](FLOW2_VERIFICATION_CHECKLIST.md) – Detailed verification commands.
- [INFRASTRUCTURE_DEPLOYMENT.md](INFRASTRUCTURE_DEPLOYMENT.md) – Full deployment guide.
