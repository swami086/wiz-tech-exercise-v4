# Application Build & Deployment (Manual Phase)

This guide covers the **manual** build and deployment of the todo application (Tasky) for the Wiz Technical Exercise V4. It aligns with the **Application Build & Deployment (Manual Phase)** ticket: build the app image, push to a container registry, and deploy to GKE with `MONGODB_URI` pointing at the MongoDB VM internal IP.

**Alternative: Terraform Kubernetes provider** — You can deploy the same app via Terraform using the Kubernetes provider. See **[APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md)** for variables (`tasky_enabled`, `tasky_image`, `tasky_mongodb_uri`, `tasky_secret_key`) and a single `terraform apply` flow.

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| **Container image** | Tasky (Go todo app) built from `tasky-main/`, pushed to Google Artifact Registry |
| **Kubernetes Deployment** | Tasky pods with `MONGODB_URI` and `SECRET_KEY` from a Secret; pod uses SA with cluster-admin (intentional misconfiguration) |
| **Kubernetes Service** | ClusterIP to expose the app on port 8080 |
| **Kubernetes Ingress** | GCP HTTP(S) Load Balancer for public access |

The app connects to MongoDB on the VM using the internal IP (firewall allows 27017 from GKE subnet only). The Tasky app uses database `go-mongodb` and collections `user` and `todos` (see `tasky-main/database/database.go`). You can use a URI without a path (e.g. `mongodb://user:pass@IP:27017`) or with `/go-mongodb`; the app will use the `go-mongodb` database.

## Prerequisites

- [Infrastructure Deployment](INFRASTRUCTURE_DEPLOYMENT.md) completed (VPC, GKE, MongoDB VM).
- [MongoDB Setup & Backup](MONGODB_SETUP_AND_BACKUP.md) completed (MongoDB with auth; app user and password).
- **kubectl** configured for the GKE cluster (`gcloud container clusters get-credentials ...`).
- **Docker** (or compatible builder) for building the image.
- **gcloud** CLI authenticated; `GOOGLE_APPLICATION_CREDENTIALS` or ADC set if using a service account.

### Get Terraform outputs

From repo root:

```bash
export GCP_PROJECT_ID="wizdemo-487311"   # or your project_id from terraform
export GCP_REGION="us-central1"          # match terraform var.region

cd terraform
MONGO_IP=$(terraform output -raw mongodb_vm_internal_ip)
CLUSTER_NAME=$(terraform output -raw gke_cluster_name)
cd ..
echo "MongoDB VM internal IP: $MONGO_IP"
echo "GKE cluster: $CLUSTER_NAME"
```

## 1. Configure kubectl for GKE

```bash
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT_ID"
kubectl get nodes
```

## 2. Create Artifact Registry repository (one-time)

If you don't have a Docker repository yet:

```bash
# Enable Artifact Registry API
gcloud services enable artifactregistry.googleapis.com --project="$GCP_PROJECT_ID"

# Create a Docker repository in the region of your GKE cluster
gcloud artifacts repositories create tasky-repo \
  --repository-format=docker \
  --location="$GCP_REGION" \
  --description="Tasky app images" \
  --project="$GCP_PROJECT_ID"
```

Image URL will be: `$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/tasky-repo/tasky`.

## 3. Build and push the image

The Tasky image includes `wizexercise.txt` (see ticket: add your name in `tasky-main/wizexercise.txt` before building). The Dockerfile copies it into the image.

From repo root, use the provided script (recommended):

```bash
./scripts/build-and-push-tasky.sh
```

Or manually:

```bash
# Authenticate Docker with Artifact Registry
gcloud auth configure-docker "$GCP_REGION-docker.pkg.dev" --quiet

# Build from tasky-main (app source; includes wizexercise.txt)
IMAGE="$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/tasky-repo/tasky:latest"
docker build -t "$IMAGE" ./tasky-main
docker push "$IMAGE"
```

## 4. Create Kubernetes Secret (MONGODB_URI and SECRET_KEY)

The app expects `MONGODB_URI` and `SECRET_KEY` (see `tasky-main/README.md`). Use the MongoDB VM internal IP and the app user credentials from MongoDB setup.

**If MongoDB auth is enabled** (recommended after MongoDB Setup & Backup):

```bash
# Get app password from the VM (see MONGODB_SETUP_AND_BACKUP.md)
# Then set:
export MONGODB_URI="mongodb://todouser:YOUR_APP_PASSWORD@${MONGO_IP}:27017/tododb"
export SECRET_KEY="your-jwt-secret-key-at-least-32-chars"
```

**If MongoDB has no auth** (e.g. before running MongoDB setup):

```bash
export MONGODB_URI="mongodb://${MONGO_IP}:27017"
export SECRET_KEY="your-jwt-secret-key-at-least-32-chars"
```

Create the Secret (run from repo root):

```bash
kubectl create namespace tasky --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic tasky-secret \
  --from-literal=MONGODB_URI="$MONGODB_URI" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  -n tasky \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or use the deploy script, which can read `MONGODB_URI` and `SECRET_KEY` from the environment or prompt you.

## 5. Deploy to GKE

**Option A – Deploy script (recommended)**

From repo root:

```bash
# Ensure MONGODB_URI and SECRET_KEY are set (or script will prompt)
./scripts/deploy-tasky-to-gke.sh
```

**Option B – Manual apply**

1. Edit `kubernetes/tasky-deployment.yaml` and set the image to your pushed image, e.g.:
   `us-central1-docker.pkg.dev/wizdemo-487311/tasky-repo/tasky:latest`.
2. Ensure the Secret `tasky-secret` exists in namespace `tasky` (see step 4).
3. Apply manifests (RBAC, then Deployment, Service, Ingress):

```bash
kubectl apply -f kubernetes/tasky-rbac.yaml
sed "s|\${TASKY_IMAGE}|$IMAGE|g" kubernetes/tasky-deployment.yaml | kubectl apply -f - -n tasky
kubectl apply -f kubernetes/tasky-service.yaml -n tasky
kubectl apply -f kubernetes/tasky-ingress.yaml -n tasky
```

## 6. Verify

```bash
kubectl get pods,svc,ingress -n tasky
kubectl logs -n tasky -l app=tasky --tail=20
```

Access the app:

- **Via Ingress (GCP Load Balancer):** Wait 5–10 minutes for the Ingress to get an external IP, then:
  ```bash
  kubectl get ingress -n tasky
  ```
  Open `http://<ADDRESS>` (port 80) in a browser.

- **Port-forward (no Load Balancer):**
  ```bash
  kubectl port-forward -n tasky svc/tasky 8080:8080
  ```
  Then open http://localhost:8080

### Verify wizexercise.txt in the running container

```bash
POD=$(kubectl get pods -n tasky -l app=tasky -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n tasky "$POD" -- cat /app/wizexercise.txt
```

### Verify cluster-admin (intentional misconfiguration)

```bash
kubectl auth can-i --list -n tasky --as=system:serviceaccount:tasky:tasky-admin-sa
# Or check a specific permission:
kubectl auth can-i create deployments --all-namespaces --as=system:serviceaccount:tasky:tasky-admin-sa
# Should return "yes"
```

## 7. Summary of scripts and manifests

| Item | Purpose |
|------|---------|
| `tasky-main/wizexercise.txt` | Your name (included in image; verify with `kubectl exec` … `cat /app/wizexercise.txt`) |
| `scripts/build-and-push-tasky.sh` | Build Tasky image from `tasky-main/`, push to Artifact Registry |
| `scripts/deploy-tasky-to-gke.sh` | Create/update Secret, apply RBAC, Deployment, Service, Ingress |
| `kubernetes/tasky-deployment.yaml` | Deployment with image, env from Secret, serviceAccountName for cluster-admin |
| `kubernetes/tasky-service.yaml` | ClusterIP Service on port 8080 |
| `kubernetes/tasky-ingress.yaml` | Ingress with GCP Load Balancer (external IP) |
| `kubernetes/tasky-rbac.yaml` | ServiceAccount + ClusterRoleBinding to cluster-admin (intentional misconfiguration) |

## Intentional misconfigurations (for demo)

As per the exercise, this phase includes an intentional misconfiguration: the Tasky pod runs with a service account bound to **cluster-admin**. Security tooling (e.g. in later tickets) will flag this. The build and deploy is otherwise standard, with `MONGODB_URI` pointing at the MongoDB VM internal IP.

## Troubleshooting

### ImagePullBackOff

- Ensure the GKE node pool’s service account can pull from Artifact Registry. In the same project, grant the GKE node SA read access (one-time):

  ```bash
  # Terraform uses custom SA gke-node-sa for the node pool (see terraform/gke.tf)
  GKE_NODE_SA="gke-node-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member="serviceAccount:${GKE_NODE_SA}" \
    --role="roles/artifactregistry.reader"
  ```
- Or use a public image for testing (not recommended for production).

### App can’t connect to MongoDB

- Check firewall: 27017 allowed from GKE subnet to MongoDB VM (see Infrastructure Deployment).
- Check `MONGODB_URI` in the Secret: correct IP, port, and (if auth enabled) username/password and database (e.g. `tododb`).
- From a pod: `kubectl run -it --rm debug --image=curlimages/curl -n tasky -- curl -v telnet://$MONGO_IP:27017` (replace `$MONGO_IP`).

### Secret already exists

To update the Secret, delete and recreate, or use:

```bash
kubectl create secret generic tasky-secret \
  --from-literal=MONGODB_URI="$MONGODB_URI" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  -n tasky --dry-run=client -o yaml | kubectl apply -f -
```

Then restart the deployment: `kubectl rollout restart deployment/tasky -n tasky`.
