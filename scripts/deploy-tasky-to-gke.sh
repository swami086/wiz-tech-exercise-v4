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

# MongoDB internal IP (for optional unauthenticated URI if user didn't set MONGODB_URI)
MONGO_IP=""
if command -v terraform &>/dev/null && [[ -d terraform ]]; then
  MONGO_IP=$(cd terraform && terraform output -raw mongodb_vm_internal_ip 2>/dev/null || true)
fi

# Prompt for Secret values if not set
if [[ -z "${MONGODB_URI:-}" ]]; then
  if [[ -n "$MONGO_IP" ]]; then
    echo "MONGODB_URI not set. Example (no auth): mongodb://${MONGO_IP}:27017"
    echo "With auth: mongodb://todouser:PASSWORD@${MONGO_IP}:27017/tododb"
  fi
  read -r -p "Enter MONGODB_URI: " MONGODB_URI
  if [[ -z "$MONGODB_URI" ]]; then
    echo "Error: MONGODB_URI is required."
    exit 1
  fi
fi
if [[ -z "${SECRET_KEY:-}" ]]; then
  read -r -p "Enter SECRET_KEY (JWT secret): " SECRET_KEY
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

# Namespace
kubectl apply -f kubernetes/namespace.yaml

# RBAC: ServiceAccount + ClusterRoleBinding (cluster-admin, intentional misconfiguration)
kubectl apply -f kubernetes/tasky-rbac.yaml

# Secret (create or replace)
kubectl create secret generic tasky-secret \
  --from-literal=MONGODB_URI="$MONGODB_URI" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  -n tasky \
  --dry-run=client -o yaml | kubectl apply -f -

# Deployment with correct image (sed replaces placeholder for portability)
sed "s|\${TASKY_IMAGE}|$IMAGE|g" kubernetes/tasky-deployment.yaml > kubernetes/tasky-deployment.generated.yaml
kubectl apply -f kubernetes/tasky-deployment.generated.yaml -n tasky
rm -f kubernetes/tasky-deployment.generated.yaml

# Service
kubectl apply -f kubernetes/tasky-service.yaml -n tasky

# Ingress (GCP Load Balancer; external IP may take 5–10 min)
kubectl apply -f kubernetes/tasky-ingress.yaml -n tasky

echo "Deployment, Service, and Ingress applied. Check: kubectl get pods,svc,ingress -n tasky"
echo "Wait 5–10 min for Ingress external IP: kubectl get ingress -n tasky"
echo "Port-forward (no LB): kubectl port-forward -n tasky svc/tasky 8080:8080"
