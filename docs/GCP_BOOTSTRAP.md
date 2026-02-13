# GCP Bootstrap (Initial Setup)

This guide covers activating the GCP project, enabling APIs, creating the automation service account, and the Terraform state bucket. It aligns with **Flow 1: Initial Setup & Bootstrapping** and the **Initial Setup & Repository Bootstrap** ticket.

## Prerequisites

- **CloudLabs**: Redeem your voucher and note the **project ID**.
- **gcloud CLI**: [Install](https://cloud.google.com/sdk/docs/install) and authenticate:

  ```bash
  gcloud auth login
  gcloud config set project YOUR_PROJECT_ID
  ```

## 1. Verify access and list resources

Confirm you can reach the project:

```bash
gcloud projects describe YOUR_PROJECT_ID
gcloud config get-value project
```

## 2. Run the bootstrap script

From the repository root:

```bash
export GCP_PROJECT_ID=your-cloudlabs-project-id
export GCP_REGION=us-central1   # optional; default us-central1
./scripts/gcp-bootstrap.sh
```

Optional overrides:

- `TF_STATE_BUCKET` – custom Terraform state bucket name (must be globally unique).
- `KEY_DIR` – directory for the service account key file (default: `./.keys`).

The script will:

- Enable APIs: Compute Engine, GKE, Cloud Storage, Logging, Security Command Center, IAM.
- Create service account `wiz-exercise-automation` with roles needed for Terraform and CI.
- Create a GCS bucket for Terraform state and turn on versioning.
- Create a key for the service account and save it under `KEY_DIR` (e.g. `.keys/`).

## 3. Store the service account key securely

- **Do not commit** the key file. It is excluded via `.gitignore` (e.g. `*-key.json`, `.keys/`).
- For **local Terraform**:

  ```bash
  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/.keys/wiz-exercise-automation-key.json
  ```

- For **GitHub Actions**, store the key content as a secret (e.g. `GCP_SA_KEY`) and configure the workflow to use it.

## 4. Validation checkpoints (Flow 1)

- [ ] You can authenticate to the CloudLabs GCP project and list resources.
- [ ] Required GCP APIs are enabled (Compute, GKE, Storage, Logging, SCC).
- [ ] GCP service account exists with appropriate IAM roles.
- [ ] Service account key is downloaded and stored in a secure location (not in git).
- [ ] Terraform state GCS bucket exists with versioning enabled.

To confirm APIs:

```bash
gcloud services list --enabled --project=YOUR_PROJECT_ID | grep -E "compute|container|storage|logging|securitycenter"
```

To confirm the bucket:

```bash
gsutil ls -L -b gs://YOUR_BUCKET_NAME
# Expect "Versioning: Enabled" (or equivalent).
```
