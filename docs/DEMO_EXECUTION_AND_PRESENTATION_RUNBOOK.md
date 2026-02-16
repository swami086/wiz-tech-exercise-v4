# Demo Execution & Presentation Runbook

This runbook supports a **structured end-to-end demo of the CI/CD flow** for the Wiz Technical Exercise. Use it for live presentations or self-validation.

## Quick start

From the repository root:

```bash
# Full demo: pre-requisites → local CI gates → optional GitHub → build/push → deployment verification
./Demo/demo-cicd-end-to-end.sh

# Skip GitHub section (e.g. no gh or no token)
SKIP_GITHUB_DEMO=1 ./Demo/demo-cicd-end-to-end.sh

# Only run local CI gate simulation (terraform validate, container build, Trivy)
RUN_LOCAL_GATES_ONLY=1 ./Demo/demo-cicd-end-to-end.sh

# Skip build/push in Phase 3 (use existing image)
SKIP_BUILD_PUSH=1 ./Demo/demo-cicd-end-to-end.sh
```

### Demo: PR with intentional vulnerabilities (scanning showcase)

To showcase the **full PR process** and what happens when vulnerabilities are detected (status checks, Trivy scan failure, Security tab):

```bash
./Demo/create-demo-pr-vulnerabilities.sh
# Optionally also break Terraform format: ./Demo/create-demo-pr-vulnerabilities.sh --also-terraform-fmt
```

This creates a new branch (default `demo/pr-vulnerability-scanning-showcase`), downgrades the Dockerfile release image to Alpine 3.17.0 so Trivy reports CRITICAL/HIGH, pushes, and opens a PR. **In the demo:** open the PR → **Checks** tab → show failed **container-scan** and Trivy output → **Security** tab for SARIF → fix by restoring Alpine 3.19 on the same branch and push → show checks turning green. See the PR body and [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md) for details.

## Prerequisites (before demo)

| Requirement | Check |
|-------------|--------|
| GCP project | `gcloud config get-value project` or `GCP_PROJECT_ID` set; Terraform applied at least once so `project_id` output exists. |
| Docker | `docker info` |
| Terraform ≥ 1.5 | `terraform version` |
| kubectl + GKE auth | `gcloud container clusters get-credentials <cluster> --region=us-central1 --project=<project>` then `kubectl get nodes` |
| (Optional) gh CLI | `gh auth status` for Phase 2 (GitHub branch protection / workflow demo) |
| (Optional) Trivy | `trivy --version` for full container-scan simulation in Phase 1 |

Ensure infrastructure and Tasky are deployable: MongoDB VM up, Artifact Registry repo exists. Choose one deployment path:

| Path | Terraform vars | Who deploys Tasky |
|------|----------------|-------------------|
| **Terraform-managed** | `tasky_enabled = true`, `argocd_enabled = false` | Terraform Kubernetes provider |
| **Argo CD (GitOps)** | `tasky_enabled = false`, `argocd_enabled = true`, `argocd_git_repo_url` set | Argo CD syncs from Git |

See [APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md), [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md), and [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md).

## Demo narrative (presentation order)

### 1. Context (30 s)

- **What we’re showing:** CI/CD with strict security gating: every change to `main` must pass Terraform validate, container scan (Trivy CRITICAL/HIGH), and a deploy gate (build + verify; on merge, push to Artifact Registry).
- **Flows:** Local simulation of the same checks that run in GitHub Actions, then optional GitHub demo, then live deployment verification.

### 2. Phase 0 – Prerequisites (30 s)

- Run the script; it will assert `gcloud`, `docker`, `terraform`, `kubectl`, and `GCP_PROJECT_ID`.
- Mention: branch protection on `main` requires status checks `terraform-validate`, `container-scan`, `deploy` (see [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md)).

### 3. Phase 1 – CI gate simulation (2–3 min)

Phase 1 runs **locally** via the demo script, or in **GitHub Actions** via `.github/workflows/phase1.yml`:

- **Terraform:** Same as Actions: `terraform init -backend=false`, `validate`, `fmt -check`. No merge if IaC is invalid or unformatted.
- **Container:** Build Tasky image, verify `/app/wizexercise.txt`, then (if Trivy installed) run Trivy with exit code 1 on CRITICAL/HIGH. Pipeline would fail on vulnerabilities.
- **Deploy gate:** Build + content check only locally; in CI, on push to `main` the deploy workflow also pushes to Artifact Registry.

**GitHub Actions Phase 1:** Push or open a PR to `main`; the `phase1.yml` workflow runs all three gates (`terraform-validate`, `container-scan`, `deploy-gate`). Add them as required status checks for branch protection. See [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md).

### 4. Phase 2 – GitHub (optional, 1–2 min)

- Show current required status checks: `./scripts/github-require-status-checks.sh`.
- Option A: Open **GitHub → Actions**, show workflow runs for `terraform-validate`, `container-scan`, `deploy`.
- Option B: Create a small PR (e.g. edit a comment in `tasky-main`), show checks running on the PR and that merge is blocked until they pass.
- Option C: Trigger a workflow manually via **Run workflow** and show the run.

### 5. Phase 3 – Deployment verification (2 min)

**Terraform-managed path** (`tasky_enabled = true`):

- Script runs `build-and-push-tasky.sh` (unless `SKIP_BUILD_PUSH=1`), then `verify-tasky-deployment.sh`.
- Show: rollout restart, pods Running, Load Balancer IP, HTTP 200, `wizexercise.txt` in pod, cluster-admin check (intentional misconfiguration).
- Open `http://<LB_IP>` and do a quick CRUD demo; optionally show persistence after deleting one pod.

**Argo CD (GitOps) path** (`argocd_enabled = true`):

- Ensure `kubernetes/` (including `kustomization.yaml`) is pushed to the Git repo referenced by `argocd_git_repo_url`.
- Build and push image: `./scripts/build-and-push-tasky.sh`.
- Argo CD syncs from Git; verify: `kubectl get applications -n argocd`, `kubectl get pods,svc,ingress -n tasky`.
- Optional: show Argo CD UI (`kubectl port-forward -n argocd svc/argocd-server 8080:443` → https://localhost:8080), demonstrate GitOps: edit `kubernetes/`, push, watch Argo CD auto-sync.
- Open `http://<LB_IP>` or port-forward for CRUD demo.

### 6. Wrap-up (30 s)

- Emphasize: one script runs the full story from “what CI runs” to “app is live and verified.”
- **Terraform path:** CI gates → build/push → Terraform or deploy script.
- **Argo CD path:** CI gates → build/push → push manifests to Git → Argo CD syncs; Git is the source of truth.
- Point to [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md), [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md), [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md) for details.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `GCP_PROJECT_ID` | GCP project; default from `terraform output project_id` if unset. |
| `SKIP_GITHUB_DEMO=1` | Skip Phase 2 (GitHub branch protection / workflow demo). |
| `RUN_LOCAL_GATES_ONLY=1` | Run only Phase 0 + Phase 1 then exit (no deploy verification). |
| `SKIP_BUILD_PUSH=1` | In Phase 3, skip build-and-push and use existing image. |
| `GH_TOKEN` | Optional; for `gh` when running Phase 2 (or use `gh auth login`). |

When using **Argo CD**, set in `terraform.tfvars`: `argocd_enabled = true`, `tasky_enabled = false`, `argocd_git_repo_url` (your Git repo). Run `terraform apply` to install Argo CD and deploy the Application before the demo.

## Troubleshooting

- **terraform validate / fmt fails:** Fix format with `terraform fmt -recursive` in `terraform/`; fix validation errors in `.tf` files.
- **Trivy fails (CRITICAL/HIGH):** Either fix base image or tooling, or for demo only note that the pipeline would block merge and continue with `RUN_LOCAL_GATES_ONLY=1` or install a newer Trivy that matches the workflow.
- **build-and-push or verify-tasky fails:** Ensure Artifact Registry repo exists (`terraform apply`), Docker authenticated (`gcloud auth configure-docker <region>-docker.pkg.dev`), GKE credentials and `tasky` namespace exist, and MongoDB is reachable from the cluster (see [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md)).
- **gh not authenticated:** Run `gh auth login` or set `GH_TOKEN`; or set `SKIP_GITHUB_DEMO=1` to skip Phase 2.
- **Argo CD app OutOfSync or failed:** Ensure `kubernetes/` (with `kustomization.yaml`) is pushed to the repo in `argocd_git_repo_url`; check `kubectl get application tasky -n argocd -o yaml` for status. Private repos need credentials in Argo CD (see [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md)).
- **Argo CD pods ImagePullBackOff:** Private GKE nodes need Cloud NAT (`terraform/network.tf`) to pull from quay.io. A standard `terraform apply` creates it; after destroy/recreate, NAT is recreated automatically. See [INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md](INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md).
- **Error testing / recovery:** For deliberate failure scenarios and recovery steps, see [ERROR_TESTING_AND_RECOVERY_PROCEDURES.md](ERROR_TESTING_AND_RECOVERY_PROCEDURES.md). Demo script: `./scripts/run-error-recovery-tests.sh terraform-validate`.

## Related

- [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md) – Workflows, security gating, secrets, branch protection.
- [ERROR_TESTING_AND_RECOVERY_PROCEDURES.md](ERROR_TESTING_AND_RECOVERY_PROCEDURES.md) – Error testing and recovery runbook; `./scripts/run-error-recovery-tests.sh`.
- [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md) – Build, push, and verification steps.
- [APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md) – Terraform-managed Tasky deployment.
- [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md) – Deploy Tasky via Argo CD (GitOps); `./scripts/install-argocd.sh`.
- Scripts: `Demo/demo-cicd-end-to-end.sh`, `Demo/create-demo-pr-vulnerabilities.sh`, `Demo/wiz-exercise-demo-end-to-end.sh`, `Demo/showcase-iac-requirements.sh`.

### IaC (Terraform) requirements showcase

To **validate and demonstrate** that the Terraform-managed infrastructure meets every Wiz exercise requirement (VM/MongoDB, backups, bucket public access, GKE private subnet, app env, wizexercise.txt, RBAC, Ingress, data in DB), use:

```bash
# Validate only (Terraform already applied)
./Demo/showcase-iac-requirements.sh

# Run terraform apply then validate
./Demo/showcase-iac-requirements.sh --apply

# Full lifecycle: destroy → apply → validate (proves reproducibility)
./Demo/showcase-iac-requirements.sh --destroy-apply
```

The script is **factored for any terraform destroy and terraform apply**: it reads all identifiers from Terraform outputs (no hardcoded IDs), so it works after a fresh apply. It checks: VM (outdated Linux, SSH firewall 0.0.0.0/0, VM SA compute.admin), MongoDB (outdated 4.4, K8s-only access + auth, daily backup, bucket public read/list), and Web App on K8s (private subnet, MONGODB_URI, wizexercise.txt in image and in running container, cluster-admin, Ingress/LB, kubectl, proof that data is in the database via API).
