#!/usr/bin/env bash
# Deploy Tasky to GKE: create namespace and Secret from MONGODB_URI/SECRET_KEY,
# then apply Deployment and Service. Image is taken from Artifact Registry
# (same as build-and-push-tasky.sh).
# Usage: from repo root,
#   export MONGODB_URI="mongodb://user:pass@MONGO_IP:27017/tododb"
#   export SECRET_KEY="your-jwt-secret"
#   ./scripts/deploy-tasky-to-gke.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Config from env or terraform
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
REPO_NAME="${ARTIFACT_REGISTRY_REPO:-tasky-repo}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  if command -v terraform &>/dev/null && [[ -d terraform ]]; then
    GCP_PROJECT_ID=$(cd terraform && terraform output -raw project_id 2>/dev/null || true)
  fi
fi
if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: set GCP_PROJECT_ID or run from a repo with terraform/outputs (project_id)."
  exit 1
fi

# Prefer Terraform outputs so destroy/recreate works without hardcoded values
if [[ -z "${MONGODB_URI:-}" ]] && command -v terraform &>/dev/null && [[ -d "$REPO_ROOT/terraform" ]]; then
  MONGODB_URI=$(cd "$REPO_ROOT/terraform" && terraform output -raw mongodb_connection_string 2>/dev/null || true)
fi
if [[ -z "${SECRET_KEY:-}" ]]; then
  SECRET_KEY=$(openssl rand -base64 32 2>/dev/null || true)
fi

# Prompt only if still missing (e.g. no Terraform state)
if [[ -z "${MONGODB_URI:-}" ]]; then
  MONGO_IP=""
  if command -v terraform &>/dev/null && [[ -d "$REPO_ROOT/terraform" ]]; then
    MONGO_IP=$(cd "$REPO_ROOT/terraform" && terraform output -raw mongodb_vm_internal_ip 2>/dev/null || true)
  fi
  if [[ -n "$MONGO_IP" ]]; then
    echo "MONGODB_URI not set. Example (with auth): mongodb://todouser:PASSWORD@${MONGO_IP}:27017/tododb"
    echo "Or run from repo with Terraform applied to use: terraform output -raw mongodb_connection_string"
  fi
  read -r -p "Enter MONGODB_URI: " MONGODB_URI
  if [[ -z "$MONGODB_URI" ]]; then
    echo "Error: MONGODB_URI is required."
    exit 1
  fi
fi
if [[ -z "${SECRET_KEY:-}" ]]; then
  read -r -p "Enter SECRET_KEY (JWT secret, min 32 chars): " SECRET_KEY
  if [[ -z "$SECRET_KEY" ]]; then
    echo "Error: SECRET_KEY is required."
    exit 1
  fi
fi

# Ensure kubectl context
CLUSTER_NAME="${GKE_CLUSTER_NAME:-}"
if [[ -z "$CLUSTER_NAME" ]]; then
  if command -v terraform &>/dev/null && [[ -d terraform ]]; then
    CLUSTER_NAME=$(cd terraform && terraform output -raw gke_cluster_name 2>/dev/null || true)
  fi
fi
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Error: set GKE_CLUSTER_NAME or run from a repo with terraform (gke_cluster_name)."
  exit 1
fi

echo "Getting GKE credentials for cluster $CLUSTER_NAME..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT_ID"

IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPO_NAME}/tasky:latest"

# Namespace (must exist before secret)
kubectl apply -f kubernetes/namespace.yaml

# Secret (create or replace; required before deployment)
kubectl create secret generic tasky-secret \
  --from-literal=MONGODB_URI="$MONGODB_URI" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  -n tasky \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply remaining manifests via Kustomize (image substituted for portability)
# If kustomize is not available, use kubectl kustomize (Kubernetes 1.14+)
if command -v kustomize &>/dev/null; then
  kustomize build kubernetes | sed "s|tasky:latest|$IMAGE|g" | kubectl apply -f -
else
  kubectl kustomize kubernetes | sed "s|tasky:latest|$IMAGE|g" | kubectl apply -f -
fi

echo "Deployment, Service, and Ingress applied. Check: kubectl get pods,svc,ingress -n tasky"
echo "Wait 5–10 min for Ingress external IP: kubectl get ingress -n tasky"
echo "Port-forward (no LB): kubectl port-forward -n tasky svc/tasky 8080:8080"
