# Error Testing & Recovery Procedures

This document implements the **Error Testing & Recovery Procedures** ticket for the Wiz Technical Exercise: how to deliberately trigger failure scenarios, verify that controls and pipelines behave as expected, and recover from common errors. Use it for validation, demos, and incident response.

## Overview

| Area | What we test | How we recover |
|------|----------------|----------------|
| **Terraform / IaC** | Invalid config, format drift, state lock, missing vars | Fix files, unlock state, set vars |
| **CI/CD gates** | terraform-validate, container-scan, deploy-gate failures | Fix code/image/format; re-run |
| **Deployment (GKE/Tasky)** | ImagePullBackOff, app not 200, MongoDB unreachable | Fix image/auth, network, Mongo VM |
| **Argo CD** | OutOfSync, sync failed, ImagePullBackOff | Fix Git/manifests, credentials, NAT |
| **Security / detective** | Firewall, bucket IAM changes | Trigger alerts (script); review incidents |
| **Lifecycle** | Plan drift, post-apply validation failures | Align config/state; fix app/Mongo/misconfigs |

---

## 1. Terraform / IaC

### 1.1 Error: Terraform validate fails (invalid syntax or config)

**Trigger (for testing):**

- Introduce a syntax error in any `.tf` file (e.g. remove a closing brace), or reference a non-existent variable.
- From repo root:
  ```bash
  cd terraform && terraform init -backend=false && terraform validate
  ```

**Expected:** `terraform validate` exits non-zero; in CI, the `terraform-validate` job fails and blocks merge.

**Recovery:**

1. Fix the reported error in the `.tf` files.
2. Run `terraform validate` again until it passes.
3. In CI, push the fix; the workflow will re-run.

### 1.2 Error: Terraform format check fails (fmt -check)

**Trigger:**

- Change indentation or spacing in a `.tf` file (e.g. add extra spaces).
- Run: `terraform fmt -check -recursive -diff` in `terraform/`.

**Expected:** Command exits non-zero; CI `terraform-validate` job fails.

**Recovery:**

```bash
cd terraform
terraform fmt -recursive
git add -A && git status   # review, then commit
```

Re-run the workflow or push to trigger CI again.

### 1.3 Error: Terraform state lock

**Trigger:** A previous `terraform apply` or `plan` was interrupted, or another process is holding the lock.

**Symptom:** `Error acquiring the state lock` when running `terraform plan` or `apply`.

**Recovery:**

1. Confirm no other Terraform process is running (e.g. in another terminal or CI run).
2. If the lock is stale (process died), force-unlock using the Lock ID from the error message:
   ```bash
   cd terraform
   terraform force-unlock <LOCK_ID>
   ```
3. Re-run `terraform plan` or `apply`.

### 1.4 Error: Missing or invalid variables

**Trigger:** Run `terraform plan` without `terraform.tfvars` or with empty/invalid values (e.g. `tasky_enabled = true` but `tasky_mongodb_uri` and `tasky_secret_key` empty when preconditions require them).

**Recovery:**

- Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and set at least:
  - `project_id`
  - `mongodb_admin_password`, `mongodb_app_password` (min 32 chars)
- If Tasky is enabled, set `tasky_mongodb_uri` and `tasky_secret_key` (or use Terraform defaults if your config allows).
- Re-run `terraform plan` / `apply`.

### 1.5 Error: Plan shows changes (drift) after apply

**Trigger:** Manual change in GCP (e.g. a firewall rule edited in Console), or code/tfvars changed without apply.

**Verify:** Run lifecycle validation:

```bash
export GCP_PROJECT_ID=your-project-id
./scripts/validate-terraform-lifecycle.sh plan
```

**Expected:** Exit 2 if there are changes; exit 0 only when plan is empty.

**Recovery:**

- **Intentional drift:** Run `terraform apply` to align state with code (or adjust code to match reality).
- **Unintentional drift:** Revert manual changes in GCP, or run `terraform apply` to re-apply desired state.

---

## 2. CI/CD gates (Phase 1)

### 2.1 Error: terraform-validate job fails

**Causes:** Invalid Terraform (validate) or unformatted files (fmt -check). Same as sections 1.1 and 1.2.

**Recovery:** Fix the Terraform code and formatting locally (`terraform fmt -recursive`, fix syntax), then push. Branch protection will require the check to pass before merge.

### 2.2 Error: container-scan job fails (Trivy CRITICAL/HIGH)

**Trigger:** Base image or dependencies introduce CRITICAL or HIGH vulnerabilities; Trivy is run with `exit-code: 1` for those severities.

**Recovery:**

- Update base image or dependencies in `tasky-main/Dockerfile` and application stack; re-run the workflow.
- For demo only, you can note that the pipeline correctly blocks merge; optionally use `RUN_LOCAL_GATES_ONLY=1` in the demo script to skip full deploy while showing gate behavior.

### 2.3 Error: deploy-gate job fails (build or wizexercise.txt)

**Trigger:** Docker build fails, or `/app/wizexercise.txt` is missing or empty in the image.

**Recovery:**

- Fix Dockerfile and ensure `wizexercise.txt` is copied into the image at `/app/wizexercise.txt`.
- Re-run the workflow (or push a fix).

### 2.4 Simulating CI failures locally (demo)

Use the script that temporarily introduces a controlled failure, then restores:

```bash
./scripts/run-error-recovery-tests.sh terraform-validate
```

This (optionally) breaks Terraform format, runs validate/fmt-check to show failure, then restores and re-runs to show recovery. See script usage for other modes.

---

## 3. Deployment (GKE / Tasky)

### 3.1 Error: kubectl cannot connect to GKE

**Symptom:** `verify-tasky-deployment.sh` or `kubectl get namespace tasky` fails with message about `gke-gcloud-auth-plugin` or “getting credentials”.

**Recovery:**

1. Install the GKE auth plugin: `gcloud components install gke-gcloud-auth-plugin` (or use an SDK that includes it).
2. Get credentials:
   ```bash
   gcloud container clusters get-credentials CLUSTER_NAME --region=us-central1 --project=GCP_PROJECT_ID
   ```
3. Confirm: `kubectl get nodes`.

Terraform and the cluster are unchanged; only local `kubectl` access is fixed.

### 3.2 Error: Namespace or deployment missing (tasky)

**Symptom:** `kubectl get namespace tasky` fails or deployment `tasky` is not found.

**Recovery:**

- **Terraform-managed:** Ensure `tasky_enabled = true` and required vars are set; run `terraform apply`. Then re-run `verify-tasky-deployment.sh`.
- **Argo CD:** Ensure `kubernetes/` (including `kustomization.yaml`) is in the Git repo pointed to by `argocd_git_repo_url`; create `tasky-secret` in namespace `tasky`; sync the app: `argocd app sync tasky` or via UI.

### 3.3 Error: ImagePullBackOff

**Symptom:** Pods in `tasky` namespace show `ImagePullBackOff` or `ErrImagePull`.

**Causes:** Image not pushed, wrong tag, or GKE nodes cannot pull (e.g. private cluster without Cloud NAT for Artifact Registry).

**Recovery:**

1. Build and push: `./scripts/build-and-push-tasky.sh` (ensure Artifact Registry repo exists and Docker is authenticated).
2. Restart rollout so pods use the new image: `kubectl rollout restart deployment/tasky -n tasky`.
3. If using private GKE nodes: ensure Cloud NAT is in place (`terraform/network.tf`) so nodes can reach Artifact Registry; run `terraform apply` if needed.

### 3.4 Error: App not returning HTTP 200 / Load Balancer pending

**Symptom:** `validate-terraform-lifecycle.sh validate` reports “App HTTP 200: FAIL”, or Ingress has no external IP.

**Recovery:**

- **LB pending:** GCE Ingress can take 5–10 minutes. Wait and re-check `kubectl get ingress -n tasky`.
- **502 / unhealthy backend:** Check pod status and app logs: `kubectl describe pod -n tasky -l app=tasky`, `kubectl logs -n tasky -l app=tasky`. Ensure readiness/liveness probes and MongoDB connectivity (see 3.5).

### 3.5 Error: MongoDB unreachable (from cluster or app)

**Symptom:** App fails to connect to MongoDB; or `validate-terraform-lifecycle.sh validate` reports “MongoDB ping: FAIL”.

**Recovery:**

1. **MongoDB VM:** Ensure the VM is running and the startup script has completed (MongoDB installed, auth enabled, listening on `0.0.0.0`). If you changed the startup script, re-apply Terraform and reboot the VM:
   ```bash
   gcloud compute instances reset MONGODB_VM_NAME --zone=ZONE --project=GCP_PROJECT_ID
   ```
   Or taint and re-apply: `terraform taint google_compute_instance.mongodb` then `terraform apply`.
2. **Network:** GKE pods must reach the MongoDB VM (e.g. via VPC/peering or correct firewall). Confirm `mongodb_connection_string` in Terraform outputs and that the VM IP/hostname is reachable from the cluster.
3. **Secret:** Ensure `tasky-secret` in namespace `tasky` has the correct `MONGODB_URI` (and `SECRET_KEY`). Update if needed and restart the deployment.

---

## 4. Argo CD

### 4.1 Error: Application OutOfSync or Sync Failed

**Symptom:** Argo CD shows Application `tasky` as OutOfSync or sync fails.

**Recovery:**

- Ensure `kubernetes/` (with `kustomization.yaml`) is pushed to the repo referenced by `argocd_git_repo_url`.
- For private repos: add repo credentials in Argo CD (`argocd repo add ...`).
- Check Application status: `kubectl get application tasky -n argocd -o yaml`; fix any reported errors (e.g. wrong path, invalid manifests).
- Trigger sync: `argocd app sync tasky` or Sync in the UI.

### 4.2 Error: Argo CD pods ImagePullBackOff (e.g. quay.io)

**Symptom:** Argo CD controller or server pods cannot pull images (e.g. from quay.io).

**Recovery:** With private GKE nodes, nodes need egress (e.g. Cloud NAT) to pull from the internet. Ensure `terraform/network.tf` Cloud NAT is applied. After `terraform destroy`/recreate, re-apply so NAT is recreated; then Argo CD can pull images again. See [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md) and [DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md](DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md).

---

## 5. Security / detective controls

### 5.1 Triggering alerts (for testing)

Use the provided script to trigger firewall and/or bucket IAM changes that should fire the Wiz Exercise alerts:

```bash
export GCP_PROJECT_ID=your-project-id
./scripts/trigger-security-alert-test.sh firewall   # firewall rule update
./scripts/trigger-security-alert-test.sh bucket     # bucket IAM get/set
./scripts/trigger-security-alert-test.sh both      # both
```

**Expected:** Within a few minutes, Cloud Monitoring → Alerting → Incidents should show incidents for “[Wiz Exercise] Firewall rule create/update/delete” and/or “[Wiz Exercise] Storage bucket IAM change”.

**Recovery (for demo):** No remediation required; the exercise validates that alerts fire. Optionally acknowledge or close the incident in Monitoring.

---

## 6. Lifecycle and post-apply validation

### 6.1 Error: validate-terraform-lifecycle.sh validate fails

**Symptom:** One or more checks fail (GKE credentials, Ingress IP, App HTTP 200, CRUD path, MongoDB ping, bucket IAM misconfig, SSH firewall misconfig).

**Recovery:**

- Use the **Summary** table printed by the script to see which check failed.
- **GKE credentials:** See 3.1.
- **Ingress / App 200 / CRUD:** See 3.4 and 3.5 (ensure Tasky is deployed and MongoDB is reachable).
- **MongoDB ping:** See 3.5.
- **Bucket IAM (allUsers):** Intentional misconfig; if FAIL, the bucket may have been changed. Re-apply Terraform or restore the intended IAM for the exercise.
- **SSH firewall (0.0.0.0/0):** Intentional misconfig; ensure the firewall rule from Terraform exists and allows `0.0.0.0/0`. Re-apply if needed.

### 6.2 Error: validate-terraform-lifecycle.sh plan exits 2 (drift)

**Recovery:** See section 1.5 (align code/state or revert manual changes, then re-run plan).

---

## 7. Quick reference: scripts and commands

| Goal | Command / script |
|------|-------------------|
| Trigger security alerts (firewall / bucket IAM) | `./scripts/trigger-security-alert-test.sh [firewall\|bucket\|both]` |
| Lifecycle plan (no drift) | `./scripts/validate-terraform-lifecycle.sh plan` |
| Post-apply validation (app, Mongo, misconfigs) | `./scripts/validate-terraform-lifecycle.sh validate` |
| Verify Tasky deployment | `./scripts/verify-tasky-deployment.sh` |
| Run controlled error/recovery demo (optional) | `./scripts/run-error-recovery-tests.sh [terraform-validate]` |
| Terraform format fix | `terraform fmt -recursive` (in `terraform/`) |
| Terraform force-unlock | `terraform force-unlock <LOCK_ID>` (in `terraform/`) |

---

## Related

- [CI_CD_PIPELINES.md](CI_CD_PIPELINES.md) – Workflows and branch protection.
- [DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md](DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md) – End-to-end demo and troubleshooting.
- [CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md](CONTAINER_BUILD_AND_DEPLOYMENT_VERIFICATION.md) – Build, push, verify.
- [INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md](INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md) – Lifecycle validation and reproduce.
- [ARGO_CD_GITOPS_INTEGRATION.md](ARGO_CD_GITOPS_INTEGRATION.md) – Argo CD setup and sync.
- [GCP_SECURITY_TOOLING.md](GCP_SECURITY_TOOLING.md) – Alerts and SCC.
