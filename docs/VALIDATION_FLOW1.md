# Flow 1 Validation: Initial Setup & Repository Bootstrap

Use this checklist to confirm all acceptance criteria for the **Initial Setup & Repository Bootstrap** ticket are met.

## GCP

- [ ] **Authenticate and list resources**  
  `gcloud auth list` shows an active account; `gcloud projects describe PROJECT_ID` succeeds.

- [ ] **Required APIs enabled**  
  Compute, GKE, Storage, Logging, SCC (and IAM). Run:
  ```bash
  gcloud services list --enabled --project=PROJECT_ID | grep -E "compute|container|storage|logging|securitycenter"
  ```

- [ ] **Service account exists with appropriate IAM roles**  
  Service account `wiz-exercise-automation@PROJECT_ID.iam.gserviceaccount.com` exists and has roles used by the bootstrap script (e.g. Compute Admin, Container Admin, Storage Admin, etc.).

- [ ] **Service account key stored securely**  
  Key file is in `.keys/` or another path under `.gitignore`; not committed to git.

- [ ] **Terraform state GCS bucket with versioning**  
  Bucket exists (e.g. `PROJECT_ID-tfstate-wiz-exercise`).  
  `gsutil versioning get gs://BUCKET_NAME` shows versioning enabled.

## Repository

- [ ] **GitHub repo exists** with directories:  
  `terraform/`, `app/`, `kubernetes/`, `scripts/`, `.github/workflows/`, `docs/`.

- [ ] **`.gitignore`** excludes:  
  `.tfvars`, `*-key.json`, `.keys/`, and other sensitive patterns (see repo root `.gitignore`).

- [ ] **Branch protection** on default branch (e.g. `main`).

- [ ] **Required PR reviews** configured (e.g. 1 approval).

- [ ] **Required status checks** configured (can be empty until CI/CD workflows exist; then add workflow job names).

- [ ] **Secret scanning** enabled (repo is public or GitHub Advanced Security is enabled).

- [ ] **Dependabot alerts** enabled.

- [ ] **README** documents the exercise overview and repo structure.

## Quick commands (after bootstrap)

```bash
# GCP project and APIs
gcloud config get-value project
gcloud services list --enabled --project=YOUR_PROJECT_ID

# State bucket versioning
gsutil versioning get gs://YOUR_BUCKET_NAME

# Repo structure (from repo root)
ls -la terraform app kubernetes scripts .github/workflows docs
```

Once all items are checked, Flow 1 is complete and you can proceed to **Infrastructure Deployment (Manual Phase)**.
