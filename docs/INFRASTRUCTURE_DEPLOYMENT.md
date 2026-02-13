# Infrastructure Deployment (Manual Phase)

This guide covers the **manual** deployment of GCP infrastructure for the Wiz Technical Exercise V4 using Terraform. It aligns with the **Infrastructure Deployment (Manual Phase)** ticket: VPC, private GKE cluster, MongoDB VM, backup GCS bucket, and firewalls.

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| **VPC** | Custom VPC with two subnets: GKE (with pod/service secondary ranges) and VM |
| **GKE** | Private cluster (nodes in private subnet); control plane reachable for `kubectl` |
| **MongoDB VM** | Debian 10 (outdated), public SSH, overly permissive IAM (`roles/compute.admin`) |
| **Backup bucket** | GCS bucket with public read and public listing (intentional misconfiguration) |
| **Firewall** | SSH from `0.0.0.0/0` to VM; MongoDB (27017) from GKE only |

MongoDB installation and backup automation are in the **MongoDB Setup & Backup Automation** ticket.

## Prerequisites

- [Flow 1](VALIDATION_FLOW1.md) complete: GCP project, APIs, service account, Terraform state bucket.
- **gcloud** CLI installed and authenticated.
- **Terraform** >= 1.5.0.
- Service account key path (e.g. `.keys/wiz-exercise-automation-key.json`).

### Using project wizdemo-487311

To use the [wizdemo-487311](https://console.cloud.google.com/apis/dashboard?project=wizdemo-487311) project and update keys in `.keys/`:

1. **Log in** with the account that has access to that project (interactive):
   ```bash
   gcloud auth login
   ```
2. **Run the setup script** from the repo root (enables APIs, creates automation SA, state bucket, and writes the key to `.keys/wiz-exercise-automation-key.json`):
   ```bash
   ./scripts/setup-wizdemo-project.sh
   ```
3. Set `project_id = "wizdemo-487311"` in `terraform/terraform.tfvars` and run Terraform as in the steps below.

## 1. Configure environment

From the repo root:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/.keys/wiz-exercise-automation-key.json"
export GCP_PROJECT_ID="wizdemo-487311"
```

## 2. Backend configuration

Terraform state is stored in GCS. The state bucket was created by `scripts/gcp-bootstrap.sh` (e.g. `$GCP_PROJECT_ID-tfstate-wiz-exercise`).

Create a `backend.tf` in `terraform/` **or** pass backend config at init (do not commit `backend.tf` if it contains project-specific values).

Option A – inline at init:

```bash
cd terraform
terraform init \
  -backend-config="bucket=${GCP_PROJECT_ID}-tfstate-wiz-exercise" \
  -backend-config="prefix=terraform/state"
```

Option B – backend config file (add `backend.tf` to `.gitignore` or use a template):

```hcl
# backend.tf (do not commit if it contains your bucket name)
terraform {
  backend "gcs" {
    bucket = "wizdemo-487311-tfstate-wiz-exercise"
    prefix = "terraform/state"
  }
}
```

Then run `terraform init` (no `-backend-config` needed if you use Option B and re-run init after creating the file).

## 3. Variables

Copy the example and set your project:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set project_id (and optionally region, zone)
```

Required variable: **project_id**. Others have defaults.

## 4. Plan and apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Apply typically takes 5–10 minutes (GKE is the slowest).

## 5. Get kubectl access

After apply:

```bash
# Use region from terraform.tfvars (e.g. us-central1)
gcloud container clusters get-credentials wiz-exercise-gke \
  --region=us-central1 \
  --project="$GCP_PROJECT_ID"
kubectl get nodes
```

Use `terraform output` to see cluster name, MongoDB VM internal IP, and backup bucket name.

## 6. Next steps

- **MongoDB Setup & Backup Automation**: Install an outdated MongoDB on the VM, enable auth, and configure daily backups to the GCS bucket.
- **Application Build & Deployment**: Build the todo app image, push to a registry, and deploy to GKE with `MONGO_URI` pointing at the VM internal IP.

## Troubleshooting

### "Failed precondition: failed to check status for ...-compute@developer.gserviceaccount.com"

GKE expects the **default Compute Engine service account** (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`) to exist. Some lab or new projects don’t have it.

- **Check:** `gcloud iam service-accounts list --project=PROJECT_ID` — if you don’t see `PROJECT_NUMBER-compute@developer.gserviceaccount.com`, the default compute SA is missing.
- **Options:** In a normal GCP project, enabling Compute Engine and creating a VM that uses the default SA usually creates it. In **CloudLabs**, the project may be restricted; try another lab project where the default compute SA exists, or ask the lab provider to enable/restore it.

### "Key creation is not allowed on this service account"

If your organization has the `iam.disableServiceAccountKeyCreation` policy, you cannot create a key for the automation service account. Use **Application Default Credentials** instead:

1. Unset any existing key: `unset GOOGLE_APPLICATION_CREDENTIALS`
2. Log in with your user account (same one that has Owner on the project):  
   `gcloud auth application-default login --project=wizdemo-487311`
3. Run Terraform; it will use these credentials. No key file is needed.

The deploy script will use a key file if present in `.keys/`, otherwise it will rely on ADC.

### Automation SA cannot set IAM ("caller does not have permission")

The bootstrap service account needs **Project IAM Admin** to create IAM bindings (e.g. for the MongoDB VM). Grant it once:

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:wiz-exercise-automation@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/resourcemanager.projectIamAdmin"
```

The bootstrap script has been updated to grant this role for new runs.

## Validation (Flow 2)

Use [VALIDATION_FLOW2.md](VALIDATION_FLOW2.md) to confirm all acceptance criteria for this ticket.

## Intentional misconfigurations (for demo)

These are required by the exercise and will be detected by GCP/Wiz tooling:

- VM: outdated OS (Debian 10), SSH from internet, service account with `roles/compute.admin`.
- GCS: backup bucket with public read and public listing.
- (Later) Kubernetes: app workload with cluster-admin role (see Application/Kubernetes tickets).
