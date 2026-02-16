# Application Deployment via Terraform Kubernetes Provider

This guide covers deploying the Tasky app to GKE using the **Terraform Kubernetes provider** (ticket: Application Deployment via Terraform Kubernetes Provider). The same components as the manual kubectl path—namespace, Secret, RBAC, Deployment, Service, Ingress—are managed by Terraform in `terraform/tasky_k8s.tf`.

## What Gets Deployed (Terraform-managed)

| Component | Terraform resource |
|-----------|--------------------|
| Namespace | `kubernetes_namespace_v1.tasky` |
| Secret (MONGODB_URI, SECRET_KEY) | `kubernetes_secret_v1.tasky_secret` |
| ServiceAccount + ClusterRoleBinding (cluster-admin) | `kubernetes_service_account_v1.tasky`, `kubernetes_cluster_role_binding_v1.tasky_admin` |
| Deployment | `kubernetes_deployment_v1.tasky` |
| Service (ClusterIP) | `kubernetes_service_v1.tasky` |
| Ingress (GCP Load Balancer) | `kubernetes_ingress_v1.tasky` |

The Kubernetes provider is configured in **`terraform/kubernetes.tf`** (GKE cluster endpoint and credentials from Terraform).

## Prerequisites

- [Infrastructure Deployment](INFRASTRUCTURE_DEPLOYMENT.md) completed (VPC, GKE, MongoDB VM).
- [MongoDB Setup & Backup](MONGODB_SETUP_AND_BACKUP.md) completed (app user/password for `MONGODB_URI`).
- **Terraform apply** has been run at least once so the Artifact Registry repository exists (`terraform/artifact_registry.tf`).
- Tasky image built and pushed to the Terraform-managed Artifact Registry (e.g. `./scripts/build-and-push-tasky.sh`).
- Terraform state already has the GKE cluster (so the Kubernetes provider can authenticate).
- **For `kubectl` from your machine:** install [gke-gcloud-auth-plugin](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin) (e.g. `gcloud components install gke-gcloud-auth-plugin`). Without it, Terraform can still create resources; only local `kubectl` commands will fail.

## Variables

Tasky deployment is **opt-in**: `tasky_enabled` defaults to `false`. Enable Tasky only after supplying non-empty `tasky_mongodb_uri` and `tasky_secret_key` (Terraform will fail with a precondition error if you set `tasky_enabled = true` without them). Set variables in `terraform.tfvars` or `-var`; keep secrets out of version control.

| Variable | Description | Required when `tasky_enabled = true` |
|----------|-------------|-------------------------------------|
| `tasky_enabled` | Set to `true` to deploy Tasky via Terraform (default: `false`) | — |
| `tasky_image` | Full image URL; defaults to `REGION-docker.pkg.dev/PROJECT_ID/tasky-repo/tasky:latest` if empty | Optional (default used if empty) |
| `tasky_mongodb_uri` | MongoDB URI (use `terraform output -raw mongodb_vm_internal_ip` for IP) | Yes (non-empty) |
| `tasky_secret_key` | JWT secret key (≥32 chars) | Yes (non-empty) |

Example `terraform.tfvars` (do not commit if it contains real secrets). **Enable Tasky only after supplying the secret values:**

```hcl
tasky_enabled       = true
tasky_image         = ""   # optional; defaults from project_id/region
tasky_mongodb_uri   = "mongodb://todouser:YOUR_PASSWORD@10.0.2.2:27017/tododb"
tasky_secret_key    = "your-jwt-secret-key-at-least-32-characters-long"
```

To deploy infrastructure only (no Tasky):

```hcl
# tasky_enabled defaults to false; no need to set it unless you previously enabled Tasky
tasky_enabled = false
```

### Using real credentials after deploy

If you deployed with placeholder values in `terraform.tfvars`:

1. Edit `terraform/terraform.tfvars` and set `tasky_mongodb_uri` and `tasky_secret_key` to your real MongoDB app user password and JWT secret (≥32 chars). Use `terraform output -raw mongodb_vm_internal_ip` for the IP in the URI.
2. From `terraform/`: run `terraform apply -auto-approve` so the Secret is updated.
3. Restart the deployment so pods pick up the new secret:  
   `kubectl rollout restart deployment/tasky -n tasky`

## Steps

### 1. Build and push the image

From repo root:

```bash
./scripts/build-and-push-tasky.sh
```

Or manually build and push to the Terraform-managed repo (default: `REGION-docker.pkg.dev/PROJECT_ID/tasky-repo/tasky:latest`). The repository is created by `terraform/artifact_registry.tf`; run `terraform apply` before the first push.

### 2. Get MongoDB internal IP and set Terraform variables

```bash
cd terraform
MONGO_IP=$(terraform output -raw mongodb_vm_internal_ip)
# Then set tasky_mongodb_uri (e.g. mongodb://todouser:PASS@${MONGO_IP}:27017/tododb)
# and tasky_secret_key in tfvars or -var
```

### 3. Apply Terraform

From `terraform/`:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

If the GKE cluster is new, the first apply creates the cluster; the Kubernetes provider then uses its credentials. If the Kubernetes provider reports errors on first run (cluster not yet ready), run `terraform apply` again.

**ServiceAccount name:** The pod service account is named `tasky` (not `tasky-admin-sa`) so validation matches the spec: `kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky`. If you had an older deployment with the previous SA name, one `terraform apply` will update the SA and binding.

### 4. Verify

```bash
kubectl get pods,svc,ingress -n tasky
kubectl get ingress -n tasky   # external IP may take 5–10 min
```

Access the app:

- **Via Ingress:** after the Ingress gets an external IP, open `http://<EXTERNAL_IP>`.
- **Port-forward:** `kubectl port-forward -n tasky svc/tasky 8080:8080` then http://localhost:8080.

## Outputs

After apply, Terraform outputs (when `tasky_enabled = true`):

- `tasky_namespace` – namespace name (`tasky`).
- `tasky_ingress_name` – Ingress name; use `kubectl get ingress -n tasky` to see the external IP.

## Relation to manual deployment

- **Manual path:** [APPLICATION_BUILD_AND_DEPLOYMENT.md](APPLICATION_BUILD_AND_DEPLOYMENT.md) uses `kubectl apply` and `scripts/deploy-tasky-to-gke.sh`.
- **Terraform path (this doc):** Terraform Kubernetes provider manages the same K8s resources in one `terraform apply`.

Use one or the other for a given cluster to avoid conflicting updates. To switch from manual to Terraform, you can import existing resources or remove the manual resources and let Terraform create them.

## Intentional misconfiguration

As in the manual flow, the Tasky pod runs with a service account bound to **cluster-admin** for demo/security-tooling detection. Do not use in production.
