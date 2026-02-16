#!/usr/bin/env bash
# Verify Tasky container build & deployment (Container Build & Deployment Verification ticket).
# Run after: ./scripts/build-and-push-tasky.sh
# Ensures: GKE credentials, rollout restart, healthy pods, LB response, wizexercise.txt, cluster-admin.
# Usage: from repo root, ./scripts/verify-tasky-deployment.sh [--skip-rollout]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SKIP_ROLLOUT=false
for arg in "$@"; do
  if [[ "$arg" == "--skip-rollout" ]]; then
    SKIP_ROLLOUT=true
    break
  fi
done

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
NAMESPACE="${TASKY_NAMESPACE:-tasky}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  if command -v terraform &>/dev/null && [[ -d terraform ]]; then
    GCP_PROJECT_ID=$(cd terraform && terraform output -raw project_id 2>/dev/null || true)
  fi
fi
if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: set GCP_PROJECT_ID or run from a repo with terraform/outputs (project_id)."
  exit 1
fi

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

echo "=== Tasky deployment verification (project=$GCP_PROJECT_ID, cluster=$CLUSTER_NAME) ==="

echo ""
echo "Getting GKE credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT_ID"

# Check kubectl access; distinguish auth/plugin errors from missing namespace
KUBE_OUT=$(kubectl get namespace "$NAMESPACE" 2>&1); KUBE_EXIT=$?
if [[ $KUBE_EXIT -ne 0 ]]; then
  if echo "$KUBE_OUT" | grep -q "gke-gcloud-auth-plugin\|getting credentials\|executable.*not found"; then
    echo "Error: kubectl cannot connect to GKE. Install the GKE auth plugin:"
    echo "  gcloud components install gke-gcloud-auth-plugin"
    echo "  # or: brew install google-cloud-sdk (includes the plugin)"
    echo "Then run: gcloud container clusters get-credentials $CLUSTER_NAME --region=$GCP_REGION --project=$GCP_PROJECT_ID"
    echo ""
    echo "If Terraform has already been applied with tasky_enabled=true, the namespace and resources exist; only kubectl access from this machine is missing."
  else
    echo "Error: could not read namespace $NAMESPACE. Run Terraform first:"
    echo "  cd terraform && terraform apply -input=false -auto-approve"
    echo "  (Ensure tasky_enabled=true in tfvars; tasky_mongodb_uri/tasky_secret_key can be left empty to derive/generate.)"
    echo ""
    echo "kubectl output: $KUBE_OUT"
  fi
  exit 1
fi

# Rollout restart to pull latest image (skip if deployment doesn't exist, e.g. Argo CD hasn't synced yet)
DEPLOY_EXISTS=$(kubectl get deployment tasky -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ') || DEPLOY_EXISTS="0"
if [[ "$SKIP_ROLLOUT" != "true" ]] && [[ "${DEPLOY_EXISTS:-0}" -gt 0 ]]; then
  echo ""
  echo "Restarting deployment to pull latest image..."
  kubectl rollout restart deployment/tasky -n "$NAMESPACE"
  echo "Waiting for rollout to complete..."
  kubectl rollout status deployment/tasky -n "$NAMESPACE" --timeout=120s
elif [[ "${DEPLOY_EXISTS:-0}" -eq 0 ]]; then
  echo ""
  echo "Deployment 'tasky' not found. If using Argo CD: ensure kubernetes/ (with kustomization.yaml) is pushed to the Git repo, then: argocd app sync tasky"
fi

echo ""
echo "Pods in $NAMESPACE:"
kubectl get pods -n "$NAMESPACE" -o wide

RUNNING=$(kubectl get pods -n "$NAMESPACE" -l app=tasky --no-headers 2>/dev/null | grep -c "Running" || true)
if [[ "${RUNNING:-0}" -lt 1 ]]; then
  echo "Warning: no Running pods found. Check: kubectl describe pods -n $NAMESPACE"
fi

echo ""
echo "Load Balancer (Ingress) status:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null || true

LB_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || LB_IP=""
if [[ -z "$LB_IP" ]]; then
  echo "Load Balancer IP not yet assigned. Wait a few minutes and run: kubectl get ingress -n $NAMESPACE"
else
  echo "Load Balancer IP: $LB_IP"
  echo "Testing HTTP response..."
  if curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$LB_IP" | grep -q 200; then
    echo "  -> HTTP 200 OK (application responding)"
  else
    echo "  -> Non-200 or timeout; health checks may still be propagating."
  fi
fi

echo ""
echo "--- Security / content validation ---"

POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=tasky -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || POD_NAME=""
if [[ -n "$POD_NAME" ]]; then
  echo "wizexercise.txt in pod $POD_NAME:"
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /app/wizexercise.txt 2>/dev/null || echo "  (exec failed)"
  echo ""
  echo "Cluster-admin permission check (intentional misconfiguration):"
  kubectl auth can-i '*' '*' --as=system:serviceaccount:${NAMESPACE}:tasky 2>/dev/null || echo "  (check failed)"
else
  echo "No tasky pod found; skip exec and auth checks."
fi

echo ""
echo "=== Verification complete ==="
echo "Next: open http://${LB_IP:-<INGRESS_IP>} and test CRUD (create, read, update, delete todos)."
echo "Persistence: create a todo, then: kubectl delete pod -n $NAMESPACE -l app=tasky --force --grace-period=0 (one pod); refresh browser to confirm data persists."
