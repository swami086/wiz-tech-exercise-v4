#!/usr/bin/env bash
# Install Argo CD into the current Kubernetes cluster (Wiz Technical Exercise V4 – GitOps).
# Usage: ensure kubectl context is set (e.g. GKE), then run from repo root:
#   ./scripts/install-argocd.sh
#
# Optional: EXPOSE_UI=1 to patch argocd-server to LoadBalancer for external access.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EXPOSE_UI="${EXPOSE_UI:-0}"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

echo "Creating namespace ${NAMESPACE}..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Applying Argo CD manifests from ${INSTALL_URL}..."
kubectl apply -n "$NAMESPACE" -f "$INSTALL_URL"

echo "Waiting for argocd-server deployment to be available (up to 5m)..."
kubectl wait --for=condition=Available -n "$NAMESPACE" deployment/argocd-server --timeout=300s 2>/dev/null || true

echo "Argo CD is installed in namespace ${NAMESPACE}."
echo ""
echo "Initial admin password (change after first login):"
kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "(run: kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "To use the UI: kubectl port-forward -n $NAMESPACE svc/argocd-server 8080:443"
echo "Then open https://localhost:8080 (accept self-signed cert)."
echo ""

if [[ "${EXPOSE_UI}" == "1" ]]; then
  echo "Patching argocd-server Service to LoadBalancer..."
  kubectl patch svc argocd-server -n "$NAMESPACE" -p '{"spec": {"type": "LoadBalancer"}}'
  echo "Wait for EXTERNAL-IP: kubectl get svc -n $NAMESPACE argocd-server"
fi
