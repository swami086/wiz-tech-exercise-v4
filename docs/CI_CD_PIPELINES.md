# CI/CD Pipelines with Strict Security Gating

This document describes the GitHub Actions CI/CD pipelines for the Wiz Technical Exercise V4 and how to configure **strict security gating** so that merges to `main` require all pipeline jobs to pass.

## Two CI/CD Pipelines (requirement)

The exercise uses **at least two pipelines**:

| Pipeline | Purpose | Workflow(s) |
|----------|---------|-------------|
| **1. IaC pipeline** | Securely deploy the exercise as **Infrastructure-as-Code**. Validates and scans IaC, then runs `terraform plan` and `terraform apply` on push to `main`. | **`iac-deploy.yml`** – validate (incl. tfsec), then deploy (plan + apply). |
| **2. Application pipeline** | **Build and push** the application as a container to a registry (GCP Artifact Registry) and **trigger a Kubernetes deployment** (rollout restart) so the new image is deployed. | **`deploy.yml`** – build, verify `wizexercise.txt`, push to registry, then trigger K8s deployment. |

- **Pipeline 1 (IaC):** Triggered on changes to `terraform/**` or the workflow. On **PR**: validate + IaC scan only. On **push to main**: validate, scan, then Terraform plan and apply.
- **Pipeline 2 (Application):** Triggered on changes to `tasky-main/**` or the workflow. On **PR**: build and verify only (no push). On **push to main**: build, verify, push to Artifact Registry, then trigger Kubernetes deployment (e.g. `kubectl rollout restart`).

## Pipeline Security (VCS and scanning)

Security controls are implemented in the **VCS platform** (GitHub) and in the pipelines:

### Repository (VCS) security

- **Branch protection** on `main`: require status checks to pass before merging (see [Required status checks](#required-status-checks-branch-protection)).
- **Secret scanning** and **Dependabot** (optional; see [GITHUB_SETUP.md](GITHUB_SETUP.md)).
- **No secrets in PR code**: Workflows use `pull_request` (not `pull_request_target` with untrusted checkout); deployment and push steps run only on `push` to `main`.

### IaC scanning (before IaC deployment)

- **Terraform validate** and **format check** (`terraform validate`, `terraform fmt -check`) – must pass before merge and before IaC deploy.
- **IaC security scans** – in the IaC pipeline (wiz-iac or local): **tfsec**, **Checkov**, **Terrascan** (GCP), **TFLint**. Results uploaded as SARIF to the GitHub Security tab. Fix HIGH/CRITICAL findings before applying in production.

IaC is only deployed (Terraform apply) **after** the validate job passes in the same workflow.

### Container and application scanning (before application deployment)

- **Trivy** (container) – runs in **Phase 1 CI Gates** (`phase1.yml`) and in **container-scan.yml**. Fails the pipeline on **CRITICAL** and **HIGH** vulnerabilities (`exit-code: 1`). SARIF uploaded to Security tab.
- **Grype** (container) – additional vulnerability scan in Phase 1; SARIF uploaded to Security tab.
- **Hadolint** – Dockerfile lint in Phase 1 (`tasky-main/Dockerfile`); fails on warning by default.
- **Semgrep** (SAST) – runs on `tasky-main` (e.g. `p/golang`, `p/security-audit`); SARIF uploaded.
- **Trivy filesystem** – dependency/SCA scan on `tasky-main`; SARIF uploaded.

The application image is only pushed and deployed **after** the container-scan gate has passed (required status check on PRs, so the image that reaches `main` has been scanned).

## Workflows (reference)

All workflows live in `.github/workflows/` at the repository root.

| Workflow | Jobs | Trigger | Purpose |
|----------|------|---------|---------|
| **`iac-deploy.yml`** | `validate`, `deploy` | Push/PR to `main` (terraform or workflow) | **Pipeline 1 – IaC:** Validate + tfsec, then (on push) Terraform plan and apply. |
| **`deploy.yml`** | `deploy` | Push/PR to `main` (tasky-main or workflow) | **Pipeline 2 – Application:** Build, push to Artifact Registry, trigger K8s deployment. |
| **`phase1.yml`** | `terraform-validate`, `container-scan`, `hadolint`, `semgrep`, `trivy-fs`, `deploy-gate` | Push/PR to `main` (terraform, tasky-main, or workflow) | **Phase 1 CI gates** – Validate, Trivy + Grype, Hadolint, Semgrep, Trivy FS, deploy gate. |
| `terraform-validate.yml` | `terraform-validate` | Push/PR to `main` (terraform or workflow) | Standalone Terraform validate + format check. |
| `container-scan.yml` | `container-scan` | Push/PR to `main` (tasky-main or workflow) | Standalone Trivy scan; fails on CRITICAL/HIGH; uploads SARIF. |

## Security gating

- **Terraform**: Invalid or unformatted IaC fails the `terraform-validate` job.
- **Container**: CRITICAL or HIGH vulnerabilities in the Tasky image fail the `container-scan` job (Trivy with `exit-code: 1`, `severity: CRITICAL,HIGH`). Fix by updating base images or dependencies in `tasky-main/Dockerfile` and re-running the workflow.
- **Deploy**: On **pull requests**, the job runs a build-and-verify-only variant (no push), so the required check can complete before merge. On **push to main**, the job runs the full build, verify, and push to Artifact Registry (requires GCP credentials; see below).

## Required status checks (branch protection)

Configure branch protection so that **IaC and container image scanning pass before merge** (and before either pipeline deploys).

**Option A – Two pipelines + Phase 1 gates:**  
Require these checks so both pipelines are gated by scanning:
- `validate` (from **IaC Deploy** workflow – Terraform validate + fmt; IaC scan runs here)
- `container-scan` (from Phase 1 CI Gates or container-scan.yml)
- `deploy-gate` (from Phase 1 CI Gates) or `deploy` (from Deploy workflow)

**Option B – Phase 1 workflow only (single entry point):**  
Use `phase1.yml` to run all CI gates in one workflow:
- `terraform-validate` (from Phase 1 CI Gates)
- `container-scan` (from Phase 1 CI Gates)
- `deploy-gate` (from Phase 1 CI Gates)

**Option C – Individual workflows:**  
- `validate` (from iac-deploy.yml) or `terraform-validate` (from terraform-validate.yml)
- `container-scan`
- `deploy`

1. Go to **Settings → Code and automation → Branches → Branch protection rule for `main`**.
2. Under **Require status checks to pass before merging**, add the checks above.

Or use the script from the repo root (requires `gh` and `jq`):

```bash
# Two pipelines: IaC + Application (require validate from iac-deploy, container-scan, deploy)
./scripts/github-require-status-checks.sh "validate" "container-scan" "deploy"

# Phase 1 consolidated
./scripts/github-require-status-checks.sh "terraform-validate" "container-scan" "deploy-gate"

# Or individual workflows only
./scripts/github-require-status-checks.sh "terraform-validate" "container-scan" "deploy"
```

All checks run on pull requests (path filters apply), so they complete on PRs instead of remaining in an "Expected" state. The `deploy` job on PRs performs pre-merge build and `wizexercise.txt` validation only; the full push runs after merge on push to `main`.

## Secrets and variables

### Both pipelines (IaC and Application)

| Secret | Required | Description |
|--------|----------|-------------|
| `GCP_SA_KEY` | Yes | JSON key for a GCP service account. **IaC pipeline:** needs permissions to run Terraform (create/update GKE, VM, buckets, etc.) and access the state bucket. **Application pipeline:** needs Artifact Registry push and (for K8s trigger) GKE get-credentials. |
| `GCP_PROJECT_ID` | Yes | GCP project ID (e.g. `wizdemo-487311`). |

### IaC pipeline (`iac-deploy.yml`)

| Secret / Variable | Required | Description |
|-------------------|----------|-------------|
| `TF_STATE_BUCKET` | No | GCS bucket for Terraform state. Default: `$GCP_PROJECT_ID-tfstate-wiz-exercise`. Create via bootstrap (see [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md)). |

### Application pipeline (`deploy.yml`)

| Variable | Required | Description |
|----------|----------|-------------|
| `GKE_CLUSTER_NAME` | No | GKE cluster name for rollout trigger. Default: `wiz-exercise-gke`. |
| `GKE_REGION` | No | GKE region. Default: `us-central1`. |

To create and download a key for GitHub Actions (see [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md)):

```bash
gcloud iam service-accounts keys create .keys/wiz-exercise-automation-key.json \
  --iam-account=wiz-exercise-automation@PROJECT_ID.iam.gserviceaccount.com
```

Then in GitHub: **Settings → Secrets and variables → Actions**: add `GCP_SA_KEY` (secret), `GCP_PROJECT_ID` (secret or variable). For IaC deploy, ensure the state bucket exists and the SA can read/write it.

### Terraform validate and container-scan (no secrets)

- **terraform-validate** (and Phase 1): No secrets; runs `terraform init -backend=false` and `terraform validate` (no GCP credentials).
- **container-scan**: No secrets; builds the image locally and runs Trivy in the runner.

## Path filters

- **iac-deploy** and **terraform-validate**: Run when files under `terraform/` or the workflow file change.
- **container-scan** and **deploy**: Run when files under `tasky-main/` or their workflow file change.

This reduces unnecessary runs when only docs or scripts change.

## Best practices applied

- **Minimal permissions**: Each job uses only the permissions it needs (`contents: read`, and `security-events: write` only for container-scan for SARIF upload).
- **No `pull_request_target` with checkout from fork**: Workflows use `pull_request` and `push`; secrets are not exposed to untrusted PR code.
- **Pinned actions**: Uses stable action versions (`@v4`, `@v3`, `@v2`, `@master` where documented).
- **Security gate**: Trivy fails the pipeline on CRITICAL/HIGH vulnerabilities (`ignore-unfixed: true` to reduce noise).

## IaC in a separate repository (optional)

You can run the IaC pipeline from a dedicated repo with full security scanning (tfsec, Checkov). See [IAC_SEPARATE_REPO.md](IAC_SEPARATE_REPO.md) and the [wiz-iac](https://github.com/swami086/wiz-iac) repository.

## Related docs

- [GITHUB_SETUP.md](GITHUB_SETUP.md) – Branch protection, secret scanning, Dependabot.
- [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md) – Manual build/push and deployment verification.
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) – GCP service account and key for automation.
- [DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md](DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md) – Structured end-to-end CI/CD demo script and presentation narrative.
- [ERROR_TESTING_AND_RECOVERY_PROCEDURES.md](ERROR_TESTING_AND_RECOVERY_PROCEDURES.md) – Error testing and recovery runbook (CI gate failures, deployment, security alerts).
