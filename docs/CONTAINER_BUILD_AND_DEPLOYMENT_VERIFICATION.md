# Container Build & Deployment Verification

This document implements the **Container Build & Deployment Verification** ticket: build and push the Tasky image to Artifact Registry, then verify the full deployment (pods, Load Balancer, CRUD, persistence, and security checks).

## Prerequisites

- **Terraform applied with Tasky enabled:** from `terraform/`, run `terraform apply` with `tasky_enabled = true` and `tasky_mongodb_uri` / `tasky_secret_key` set so the namespace `tasky`, deployment, service, ingress, and RBAC exist. See [Application Deployment via Terraform Kubernetes Provider](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md).
- **GKE auth plugin for kubectl:** install `gke-gcloud-auth-plugin` so `kubectl` can talk to GKE (e.g. `gcloud components install gke-gcloud-auth-plugin`). Without it, the verification script will report that kubectl cannot connect; Terraform-created resources still exist in the cluster.
- `gcloud` CLI authenticated with your GCP project (or set `GCP_PROJECT_ID`).
- `kubectl` and Docker installed.

## Quick Run

From the repository root:

```bash
# 1. Build image and push to Artifact Registry (creates repo if missing, verifies wizexercise.txt)
./scripts/build-and-push-tasky.sh

# 2. Restart deployment and verify pods, LB, wizexercise.txt, cluster-admin
./scripts/verify-tasky-deployment.sh
```

To only re-run verification without restarting the deployment:

```bash
./scripts/verify-tasky-deployment.sh --skip-rollout
```

## Step-by-Step (Ticket-Aligned)

### 1. Artifact Registry repository

The script `build-and-push-tasky.sh` creates the repository if it does not exist:

- **Repository:** `tasky-repo`
- **Location:** `us-central1`
- **Format:** Docker  
- **Description:** "Tasky application container images for Wiz Exercise"

Manual alternative:

```bash
gcloud artifacts repositories create tasky-repo \
  --repository-format=docker \
  --location=us-central1 \
  --project=wizdemo-487311 \
  --description="Tasky application container images for Wiz Exercise"
```

### 2. Docker authentication

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
```

(The build script runs this automatically.)

### 3. Build and verify image

- **Dockerfile:** `tasky-main/Dockerfile`
- **Tag:** `us-central1-docker.pkg.dev/wizdemo-487311/tasky-repo/tasky:latest`

The build script verifies that `wizexercise.txt` is present in the image at `/app/wizexercise.txt`.

### 4. Push to Artifact Registry

Handled by `./scripts/build-and-push-tasky.sh`. Confirm with:

```bash
gcloud artifacts docker images list us-central1-docker.pkg.dev/wizdemo-487311/tasky-repo --project=wizdemo-487311
```

### 5. Deployment restart and health

`verify-tasky-deployment.sh` runs:

- `kubectl rollout restart deployment/tasky -n tasky`
- `kubectl rollout status deployment/tasky -n tasky`
- `kubectl get pods -n tasky -o wide`

All tasky pods should be `Running`.

### 6. Application accessibility

- Get Load Balancer IP: `kubectl get ingress -n tasky`
- Open in browser: `http://<LB_IP>` (e.g. `http://34.50.156.82`)
- Or: `curl -I http://<LB_IP>` → expect HTTP 200.

### 7. Functional validation

- **CRUD:** Create, read, update, and delete todo items via the web UI.
- **Persistence:** Create a todo, then restart one pod:
  ```bash
  kubectl delete pod -n tasky -l app=tasky --force --grace-period=0
  # (only one pod will be deleted; wait for replacement)
  kubectl wait --for=condition=ready pod -n tasky -l app=tasky --timeout=60s
  ```
  Refresh the browser; the todo should still be there (MongoDB persistence).

### 8. Security validation

- **wizexercise.txt in container:**
  ```bash
  POD_NAME=$(kubectl get pods -n tasky -l app=tasky -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n tasky $POD_NAME -- cat /app/wizexercise.txt
  ```
  Expected: your name or "Wiz Exercise Participant".

- **Cluster-admin (intentional misconfiguration):**
  ```bash
  kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky
  ```
  Expected: `yes`.

### 9. Screenshots for presentation

Capture:

1. Artifact Registry: repository `tasky-repo` with image `tasky:latest`.
2. GKE console: namespace `tasky`, pods Running and healthy.
3. Web UI: todo list with at least one item (after CRUD test).
4. Terminal: output of `kubectl exec ... cat /app/wizexercise.txt`.
5. Terminal: output of `kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky` showing `yes`.

## Acceptance criteria checklist

| Area | Criterion |
|------|-----------|
| **Artifact Registry** | Repository `tasky-repo` in `us-central1`; Docker auth configured; visible in console. |
| **Build & push** | Image built from `tasky-main/Dockerfile`; includes `/app/wizexercise.txt`; tagged and pushed as `us-central1-docker.pkg.dev/wizdemo-487311/tasky-repo/tasky:latest`. |
| **Deployment health** | Rollout restarted; all pods `Running`; app responds on Load Balancer IP. |
| **Functional** | CRUD works via UI; data persists in MongoDB across pod restart. |
| **Security** | `wizexercise.txt` in container with correct content; SA `tasky` has cluster-admin (`kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky` = yes). |
| **Documentation** | Screenshots as above; any issues and resolutions noted. |

## Troubleshooting

- **kubectl cannot connect / gke-gcloud-auth-plugin not found:** Install the [GKE auth plugin](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin): `gcloud components install gke-gcloud-auth-plugin` (or use a Google Cloud SDK that includes it). Terraform applies still work; only local `kubectl` and the verification script need the plugin.
- **Namespace tasky does not exist:** Run Terraform with Tasky enabled: `cd terraform && terraform apply` and set `tasky_enabled = true`, `tasky_mongodb_uri`, and `tasky_secret_key` in `terraform.tfvars`.
- **ImagePullBackOff:** Ensure the image is pushed and the GKE node pool has permission to pull from Artifact Registry (Workload Identity or node SA with `roles/artifactregistry.reader`).
- **Load Balancer IP pending:** GCE Ingress can take 5–10 minutes; check `kubectl describe ingress -n tasky`.
- **502 / unhealthy backend:** Wait for readiness/liveness; check `kubectl describe pod -n tasky` and app logs.
- **MongoDB connection:** Tasky uses `tasky_mongodb_uri` from Terraform (e.g. `mongodb://todouser:***@10.0.2.2:27017/tododb`). Ensure the MongoDB VM is up and reachable from the GKE cluster.

## Related

- **Terraform:** `terraform/tasky_k8s.tf` (image reference, replicas, probes, ingress).
- **Build script:** `scripts/build-and-push-tasky.sh`.
- **Verification script:** `scripts/verify-tasky-deployment.sh`.
- **Epic:** Wiz Technical Exercise Implementation; next tickets: CI/CD Pipelines, GCP Security Tooling.
