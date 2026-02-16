#!/usr/bin/env bash
# Build Tasky image from tasky-main/ and push to Google Artifact Registry.
# Requires: gcloud, Docker, GCP_PROJECT_ID and GCP_REGION set (or defaults).
# Usage: from repo root, ./scripts/build-and-push-tasky.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Config: prefer env, then terraform output. Use Terraform-managed Artifact Registry when available.
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

# Prefer Terraform-managed repo URL (apply must have been run so the repo exists)
IMAGE=""
if command -v terraform &>/dev/null && [[ -d terraform ]]; then
  REPO_URL=$(cd terraform && terraform output -raw artifact_registry_repository_url 2>/dev/null || true)
  REPO_ID=$(cd terraform && terraform output -raw artifact_registry_repository_id 2>/dev/null || true)
  if [[ -n "$REPO_URL" ]]; then
    IMAGE="${REPO_URL}/tasky:latest"
    [[ -n "$REPO_ID" ]] && REPO_NAME="$REPO_ID"
  fi
  REGION_FROM_TF=$(cd terraform && terraform output -raw region 2>/dev/null || true)
  [[ -n "$REGION_FROM_TF" ]] && GCP_REGION="$REGION_FROM_TF"
fi
if [[ -z "$IMAGE" ]]; then
  IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPO_NAME}/tasky:latest"
fi

# Terraform creates the Artifact Registry repository; ensure it exists before push (run terraform apply first).
if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$GCP_REGION" --project="$GCP_PROJECT_ID" &>/dev/null; then
  echo "Error: Artifact Registry repository '$REPO_NAME' not found. Run 'terraform apply' first to create it (see terraform/artifact_registry.tf)."
  exit 1
fi

echo "Configuring Docker for Artifact Registry..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

# Build for linux/amd64 so the image runs on GKE nodes (avoids "no match for platform in manifest")
echo "Building image from tasky-main/ (linux/amd64 for GKE)..."
docker build --platform linux/amd64 -t "$IMAGE" ./tasky-main

echo "Verifying wizexercise.txt is in the image..."
docker run --rm --platform linux/amd64 --entrypoint cat "$IMAGE" /app/wizexercise.txt | grep -q . || {
  echo "Error: wizexercise.txt not found or unreadable in image."
  exit 1
}

echo "Pushing $IMAGE ..."
docker push "$IMAGE"

echo "Verifying image in Artifact Registry..."
gcloud artifacts docker images list "$(echo "$IMAGE" | cut -d'/' -f1-3)" \
  --project="$GCP_PROJECT_ID" --include-tags 2>/dev/null | head -5 || true

echo "Done. Image: $IMAGE"
