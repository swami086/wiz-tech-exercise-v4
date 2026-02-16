# End-to-end flow: both pipelines (step by step)

This document describes how the **IaC pipeline** and the **application pipeline** work together, in order, from trigger to running app.

---

## Overview: two pipelines

| Pipeline | Repo | Workflow(s) | What it does |
|----------|------|-------------|--------------|
| **IaC pipeline** | Main (Wiz) or **wiz-iac** | IaC Deploy (and in wiz-iac: IaC Destroy) | Provisions GCP + GKE, Argo CD, tasky namespace, tasky-secret. Does **not** deploy the app. |
| **App pipeline** | Main (Wiz) | Phase 1 CI Gates → Deploy | Builds image, runs security gates, then (on success) pushes image, updates Argo CD Application, and rolls out the app. |

The **app** is deployed only by the **app pipeline** (Deploy workflow). IaC only prepares the cluster and Argo CD.

---

## Flow 1: IaC pipeline (infrastructure first)

**Trigger:** Push to `main` that touches `terraform/**` or the IaC workflow file, **or** manual run (`workflow_dispatch`).

- **Main repo:** `.github/workflows/iac-deploy.yml`  
- **wiz-iac repo:** `.github/workflows/iac-deploy.yml` (same idea; destroy is separate)

### Step-by-step (IaC)

1. **Validate**  
   - Checkout → `terraform init -backend=false` → `terraform validate` → `terraform fmt -check`.  
   - Fails fast if Terraform is invalid.

2. **Scan report (in parallel with deploy on main)**  
   - Run tfsec, write `docs/scan-reports/iac-deploy-scan-report.md`.  
   - Open a PR from branch `ci/scan-report-iac-deploy-<run_id>` with that report.  
   - Does not block deploy.

3. **Deploy (only on push to main, and only if MongoDB secrets are set in this repo)**  
   - **Main repo:** Runs only when `github.event_name == 'push' && github.ref == 'refs/heads/main'`. If `MONGODB_ADMIN_PASSWORD` / `MONGODB_APP_PASSWORD` are not set, deploy is skipped (validate still passed).  
   - **wiz-iac:** Same idea; deploy runs on push to main or `workflow_dispatch` from main.  
   - Steps:  
     - Check secrets (main repo) or use tfvars/env (wiz-iac).  
     - Checkout → GCP auth → `terraform init` (GCS backend) → `terraform plan -out=tfplan` → `terraform apply -auto-approve tfplan`.  
   - Result: **VPC, GKE cluster, Artifact Registry (if in Terraform), MongoDB VM (if used), Argo CD installed, `tasky` namespace, `tasky-secret`.**  
   - **No Argo CD Application is created by IaC** — that is done by the app pipeline.

4. **Optional: application URL**  
   - After apply, the workflow may try to read the tasky Ingress IP and write it to the job summary. The app may not be reachable until the **app pipeline** has run at least once.

**Outcome:** Cluster and Argo CD are ready; namespace and secret exist. App is not deployed yet.

---

## Flow 2: App pipeline (build → gates → deploy)

**Trigger:**  
- Push to `main` that touches `tasky-main/**`, `terraform/**`, or `phase1.yml` → **Phase 1** runs.  
- When **Phase 1** completes **successfully** and the triggering event was a **push** → **Deploy** runs automatically (`workflow_run`).  
- Or run **Deploy** manually (`workflow_dispatch`).

### Phase 1 CI Gates – step-by-step

1. **terraform-validate**  
   - Checkout → `terraform init -backend=false` → `terraform validate` → `terraform fmt -check`.  
   - Ensures Terraform in the repo is valid (no apply here).

2. **container-scan** (single build for Phase 1)  
   - Build image `tasky:${{ github.sha }}` **once**.  
   - Verify `/app/wizexercise.txt` in image.  
   - Trivy (CRITICAL/HIGH) and Grype (critical) **gating**; upload Trivy/Grype SARIF to Security tab.  
   - Write Trivy image table to `trivy-image-table.txt` and **upload as artifact** for scan-report.

3. **hadolint**  
   - Lint `tasky-main/Dockerfile` (failure threshold: warning).

4. **semgrep**  
   - SAST on `tasky-main` (Golang + security-audit); upload SARIF.

5. **trivy-fs**  
   - Trivy filesystem scan on `tasky-main`; upload SARIF.

6. **scan-report** (needs: terraform-validate, container-scan, hadolint, semgrep, trivy-fs)  
   - **No image build:** download `trivy-image-table` artifact from container-scan for the “Trivy (container image)” section.  
   - Run Trivy FS, Hadolint, Semgrep (no Docker) and write `docs/scan-reports/phase1-scan-report.md`.  
   - Open PR from branch `ci/scan-report-phase1-<run_id>`.

7. **deploy-gate** (needs: same as scan-report)  
   - **No image build:** image was already built and verified in container-scan.  
   - Writes to job summary: “Phase 1 CI Gates passed; Deploy workflow will run after this workflow completes.”

**Outcome:** All gates passed. No image push and no Kubernetes changes yet.

---

### Deploy workflow – step-by-step (runs after Phase 1 success or manually)

**Condition:**  
- Runs only if: `workflow_run` with Phase 1 **success** and trigger = **push**, **or** `workflow_dispatch`.  
- Uses the same commit as Phase 1 when triggered by `workflow_run` (`workflow_run.head_sha`).

1. **Checkout**  
   - Checkout at `github.sha` or `workflow_run.head_sha`.

2. **GCP auth & gcloud**  
   - Authenticate with `GCP_SA_KEY`, set project.

3. **Ensure Artifact Registry repo**  
   - If repo doesn’t exist, create it (or rely on Terraform-created repo).

4. **Configure Docker for Artifact Registry**  
   - `gcloud auth configure-docker <region>-docker.pkg.dev`.

5. **Build and verify image**  
   - Build `tasky` for `linux/amd64`, tag with SHA (and for push: full Artifact Registry path).  
   - Verify `wizexercise.txt` in image.

6. **Push to Artifact Registry**  
   - Push image with SHA tag.

7. **Tag and push `latest`**  
   - Tag same image as `.../tasky:latest` and push.

8. **Get GKE credentials**  
   - `gcloud container clusters get-credentials` for the cluster (e.g. `wiz-exercise-gke`).

9. **Apply Argo CD Application**  
   - Substitute in `argocd/application-tasky.yaml`:  
     - `REPO_URL_PLACEHOLDER` → this repo URL.  
     - `TARGET_REVISION_PLACEHOLDER` → commit SHA (the one we just built).  
     - `IMAGE_PLACEHOLDER` → full Artifact Registry image (e.g. `.../tasky:latest`).  
   - Run: `kubectl apply -n argocd -f -` (piped from `sed`).  
   - Argo CD then syncs **this repo**, path `kubernetes/`, at that **commit SHA**, with that **image** override.

10. **Trigger Kubernetes deployment (rollout)**  
    - `kubectl rollout restart deployment/tasky -n tasky`.  
    - `kubectl rollout status ... --timeout=120s`.  
    - New pods pull the image just pushed (e.g. `tasky:latest`).

**Outcome:** Image is in Artifact Registry; Argo CD Application points at the built commit; app is running with the new image.

---

## How the two pipelines interact (order of operations)

1. **First-time / greenfield**  
   - Run **IaC pipeline** (main or wiz-iac) so that GKE, Argo CD, namespace, and secret exist.  
   - Then run **app pipeline**: push to main (or run Phase 1 then Deploy, or trigger Deploy manually).  
   - Phase 1 gates run; on success, Deploy builds, pushes, applies the Application, and restarts the deployment.  
   - App is live at the Ingress IP (e.g. from LoadBalancer).

2. **Infrastructure change only**  
   - Change only `terraform/**` (and/or IaC workflow) → **IaC Deploy** runs (validate, optional scan report PR, deploy on main if secrets set).  
   - **Phase 1 / Deploy do not run** (no change under `tasky-main/**` or `phase1.yml`).  
   - No new app image; existing app keeps running.

3. **Application change only**  
   - Change only `tasky-main/**` or `phase1.yml` → **Phase 1** runs (all gates).  
   - **IaC Deploy does not run** (no change under `terraform/**` or `iac-deploy.yml`).  
   - When Phase 1 succeeds (push to main), **Deploy** runs: new image, Argo CD Application updated to that commit, rollout.

4. **Both infra and app changed**  
   - Push touches both `terraform/**` and `tasky-main/**` (or both workflows).  
   - **IaC Deploy** and **Phase 1** can both run (different path filters).  
   - IaC deploy (if on main with secrets) updates infra.  
   - Phase 1 gates run; on success, Deploy runs and deploys the app.

5. **Manual deploy**  
   - **Deploy** can be run via `workflow_dispatch` without a recent Phase 1 run (e.g. to redeploy current main).  
   - It will build/push from the branch you run it from and apply the Application for that commit.

---

## Summary diagram (logical order)

```
[Push to main]
       │
       ├── Paths: terraform/**, iac-deploy.yml
       │         → IaC Deploy: validate → (scan report PR) → [deploy: plan/apply]
       │         → Result: GKE, Argo CD, namespace, secret (no app deploy)
       │
       └── Paths: tasky-main/**, terraform/**, phase1.yml
                  → Phase 1 CI Gates: validate, container scan (1 build), hadolint, semgrep, trivy-fs
                                     → scan-report PR (uses artifact), deploy-gate (no build)
                  → Phase 1 success (push) → Deploy workflow
                                            → build → push image → apply Argo CD Application (SHA + image)
                                            → kubectl rollout restart deployment/tasky
                  → Result: New image in registry; Argo CD synced to that commit; app running new image
```

---

## Workflow optimizations (duplicate builds removed)

Previously, the **same image was built up to 4 times** when Phase 1 → Deploy ran:

| Location        | Before                         | After                          |
|----------------|---------------------------------|--------------------------------|
| container-scan | 1 build                         | 1 build (unchanged)            |
| scan-report    | 1 build (for Trivy image in report) | **0 builds** – uses artifact from container-scan |
| deploy-gate    | 1 build (verify again)          | **0 builds** – relies on container-scan |
| Deploy workflow| 1 build (push)                  | 1 build (required; separate run) |

**Phase 1 now builds the image once** (in container-scan). scan-report gets the Trivy image table via `actions/upload-artifact` / `download-artifact`. deploy-gate only asserts that all gates passed; the image was already built and verified in container-scan.

**Deploy still builds once** because it runs in a separate workflow and must push to Artifact Registry; sharing the image would require Phase 1 to push (e.g. as `tasky:$SHA`), which would add GCP auth and push on every Phase 1 run (including PRs). Keeping one build in Deploy is the current trade-off.

**Optional further optimization:** Phase 1 could push the image as `tasky:$SHA` on push to main only; then Deploy would pull, tag as `latest`, push and rollout (no build in Deploy). That would require GCP credentials in Phase 1 for push-to-main runs.

---

## Repos at a glance

- **Main repo (Wiz):** Holds Terraform, `tasky-main/`, `kubernetes/`, `argocd/application-tasky.yaml`, and the workflows above. Both **IaC Deploy** and **Phase 1 + Deploy** run here (on different path triggers).  
- **wiz-iac repo:** Dedicated IaC repo; its **IaC Deploy** (and **IaC Destroy**) are separate from the main repo. Use one or the other for provisioning; the **app** is always deployed by the main repo’s **Deploy** workflow.

This is the full step-by-step flow for both pipelines and how they work together.
