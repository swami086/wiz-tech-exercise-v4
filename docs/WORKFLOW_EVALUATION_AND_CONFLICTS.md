# Workflow evaluation and conflict resolution

Evaluation of CI/CD pipelines across the **main repo (Wiz)** and **wiz-iac** repo to ensure no conflicts.

---

## 1. Main repo (Wiz) – workflow summary

| Workflow | Triggers | Purpose |
|----------|----------|---------|
| **IaC Deploy** | push/PR (terraform/**, iac-deploy.yml), workflow_dispatch | Validate Terraform, tfsec scan, scan report PR, Terraform deploy (push to main only) |
| **Phase 1 CI Gates** | push/PR (terraform/**, tasky-main/**, phase1.yml), workflow_dispatch | Terraform validate, container scan (Trivy/Grype), Hadolint, Semgrep, Trivy FS, scan report PR, deploy-gate (no build; gate only) |
| **Deploy (Build, Push, K8s)** | workflow_run (Phase 1 completed), workflow_dispatch | Build image, push to Artifact Registry, apply Argo CD Application, K8s rollout (only after Phase 1 or manual) |

**Removed as redundant:** Standalone **Container Scan** and **Terraform Validate** workflows were removed; Phase 1 already runs container scan (Trivy/Grype) and Terraform validate. An orphan `tasky-main/.github/workflows/build-and-publish.yml` (never run by GitHub; pushes to ghcr.io) was also removed in favour of root **Deploy** (Artifact Registry).

### Path overlap (intended)

- **terraform/** changes → IaC Deploy and/or Phase 1 (depending on paths).
- **tasky-main/** changes → Phase 1 (container scan + other gates).
- **Phase 1** does not deploy; **Deploy** workflow is the only one that pushes and rolls out (triggered after Phase 1 or manually).

### Scan report PRs (main repo)

- **IaC Deploy** → branch `ci/scan-report-iac-deploy-<run_id>`, file `docs/scan-reports/iac-deploy-scan-report.md`.
- **Phase 1** → branch `ci/scan-report-phase1-<run_id>`, file `docs/scan-reports/phase1-scan-report.md`.
- Different branches and files → no conflict.

---

## 2. wiz-iac repo – workflow summary

| Workflow | Triggers | Purpose |
|----------|----------|---------|
| **IaC Deploy** | push/PR (main), workflow_dispatch | Validate, tfsec scan report PR, Terraform plan/apply (push or workflow_dispatch from main) |
| **IaC Destroy** | workflow_dispatch only | Terraform destroy, destroy report PR |

### Deploy condition (wiz-iac)

- Deploy job runs when: `github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')`.
- So: push to main or manual run from main both deploy; manual run from another branch does not deploy.

### Scan/destroy report PRs (wiz-iac)

- **IaC Deploy** → `ci/scan-report-iac-deploy-<run_id>`, `docs/scan-reports/iac-deploy-scan-report.md`.
- **IaC Destroy** → `ci/destroy-report-<run_id>`, `docs/scan-reports/destroy-report.md`.
- No overlap.

---

## 3. Changes made to avoid conflicts

### 3.1 wiz-iac – deploy on workflow_dispatch from main

- **Issue:** Deploy job used `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`, so manual run never deployed.
- **Change:** Condition updated to `github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')` so deploy runs on push to main or when manually triggered from main.

### 3.2 Main repo – single deploy path (no duplicate deploy)

- **Issue:** Phase 1 deploy-gate and Deploy workflow both pushed the image and did K8s rollout when Phase 1 completed on push → duplicate deploy.
- **Changes:**
  - **Deploy workflow** now triggers only on `workflow_run` (Phase 1 completed) and `workflow_dispatch`. Push/PR triggers were removed so it does not run on every push to tasky-main.
  - **Phase 1 deploy-gate** now only builds and verifies the image; all push/rollout steps were removed. Deploy (push + K8s) runs only in the Deploy workflow after Phase 1 succeeds or on manual run.

### 3.3 deploy.yml permissions

- **Change:** `id-token: write` added to the deploy job for GCP auth compatibility.

---

## 4. Resulting flow (main repo)

1. **Push to main (tasky-main/** or phase1.yml):** Phase 1 runs (scans + build/verify). No deploy in Phase 1.
2. **Phase 1 completes successfully:** Deploy workflow runs via `workflow_run`, builds, pushes image, runs K8s rollout (single deploy).
3. **Push to main (terraform/**):** IaC Deploy runs (validate, scan report PR, and deploy if secrets set).
4. **Manual:** Any workflow can be run via workflow_dispatch; wiz-iac deploy runs when triggered from main.

---

## 5. Cross-repo notes

- **Main repo** and **wiz-iac** are separate repos; no shared triggers or job names.
- Scan/destroy report branches and file names are unique per workflow and per repo.
- `peter-evans/create-pull-request` uses `run_id` in branch names, so concurrent runs do not clash.

---

## 6. Argo CD: IaC vs app repo

- **IaC (wiz-iac):** Installs Argo CD and creates the `tasky` namespace + `tasky-secret` (MongoDB URI, secret key). It does **not** create the Argo CD Application.
- **App repo:** The Deploy workflow applies the Argo CD Application (`argocd/application-tasky.yaml`) with the repo URL and image substituted, then runs `kubectl rollout restart`. So the **application is deployed by the app repo**, not by IaC.

## 7. Optional follow-ups

- Add repo labels (e.g. `scan-report`, `automated`) and pass them to `create-pull-request` for filtering.
- If wiz-iac adds more scanners (e.g. Checkov, TFLint), include their output in the same `docs/scan-reports/iac-deploy-scan-report.md` or a dedicated file and keep a single report PR per run.
