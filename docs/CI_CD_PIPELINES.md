# CI/CD Pipelines with Strict Security Gating

This document describes the GitHub Actions CI/CD pipelines for the Wiz Technical Exercise V4 and how to configure **strict security gating** so that merges to `main` require all pipeline jobs to pass.

## Workflows

All workflows live in `.github/workflows/` at the repository root.

| Workflow | Job name | Trigger | Purpose |
|----------|----------|---------|---------|
| `terraform-validate.yml` | `terraform-validate` | Push/PR to `main` (terraform or workflow changes) | Terraform init (no backend), validate, and format check for IaC. |
| `container-scan.yml` | `container-scan` | Push/PR to `main` (tasky-main or workflow changes) | Build Tasky image, run Trivy; **fails on CRITICAL/HIGH** vulnerabilities. Optionally uploads SARIF to the Security tab. |
| `deploy.yml` | `deploy` | Push/PR to `main` (tasky-main or workflow changes) | **On PR:** build Tasky image and verify `wizexercise.txt` (no push). **On push to main:** same build/verify plus push to GCP Artifact Registry (`tasky-repo`) as `$SHA` and `latest`. |

## Security gating

- **Terraform**: Invalid or unformatted IaC fails the `terraform-validate` job.
- **Container**: CRITICAL or HIGH vulnerabilities in the Tasky image fail the `container-scan` job (Trivy with `exit-code: 1`, `severity: CRITICAL,HIGH`).
- **Deploy**: On **pull requests**, the job runs a build-and-verify-only variant (no push), so the required check can complete before merge. On **push to main**, the job runs the full build, verify, and push to Artifact Registry (requires GCP credentials; see below).

## Required status checks (branch protection)

To enforce that all three jobs pass before merging into `main`:

1. Go to **Settings → Code and automation → Branches → Branch protection rule for `main`**.
2. Under **Require status checks to pass before merging**, add:
   - `terraform-validate`
   - `container-scan`
   - `deploy`

Or use the script from the repo root (requires `gh` and `jq`):

```bash
./scripts/github-require-status-checks.sh "terraform-validate" "container-scan" "deploy"
```

All three checks run on pull requests (path filters apply), so they complete on PRs instead of remaining in an "Expected" state. The `deploy` job on PRs performs pre-merge build and `wizexercise.txt` validation only; the full push runs after merge on push to `main`.

## Secrets and variables

### Deploy workflow (`deploy.yml`)

| Secret | Required | Description |
|--------|----------|-------------|
| `GCP_SA_KEY` | Yes | JSON key for a GCP service account that can push to Artifact Registry (e.g. `Artifact Registry Writer` and `Storage Object Viewer` if the repo is created by Terraform; or create the repo manually and grant the SA access). |
| `GCP_PROJECT_ID` | Yes | GCP project ID (e.g. `wizdemo-487311`). Can be stored as a repository secret or variable. |

To create and download a key for GitHub Actions (see [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md)):

```bash
gcloud iam service-accounts keys create .keys/wiz-exercise-automation-key.json \
  --iam-account=wiz-exercise-automation@PROJECT_ID.iam.gserviceaccount.com
```

Then in GitHub: **Settings → Secrets and variables → Actions → New repository secret**: name `GCP_SA_KEY`, value = contents of the JSON file. Add `GCP_PROJECT_ID` as a secret (or repository variable) with your project ID.

### Terraform and container-scan

- **terraform-validate**: No secrets; runs `terraform init -backend=false` and `terraform validate` (no GCP credentials).
- **container-scan**: No secrets; builds the image locally and runs Trivy in the runner.

## Path filters

- **terraform-validate**: Runs when files under `terraform/` or the workflow file change.
- **container-scan** and **deploy**: Run when files under `tasky-main/` or their workflow file change.

This reduces unnecessary runs when only docs or scripts change.

## Best practices applied

- **Minimal permissions**: Each job uses only the permissions it needs (`contents: read`, and `security-events: write` only for container-scan for SARIF upload).
- **No `pull_request_target` with checkout from fork**: Workflows use `pull_request` and `push`; secrets are not exposed to untrusted PR code.
- **Pinned actions**: Uses stable action versions (`@v4`, `@v3`, `@v2`, `@master` where documented).
- **Security gate**: Trivy fails the pipeline on CRITICAL/HIGH vulnerabilities (`ignore-unfixed: true` to reduce noise).

## Related docs

- [GITHUB_SETUP.md](GITHUB_SETUP.md) – Branch protection, secret scanning, Dependabot.
- [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md) – Manual build/push and deployment verification.
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) – GCP service account and key for automation.
