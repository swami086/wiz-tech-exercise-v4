#!/usr/bin/env bash
# Build Tasky image from tasky-main/ and push to Google Artifact Registry.
# Requires: gcloud, Docker, GCP_PROJECT_ID and GCP_REGION set (or defaults).
# Usage: from repo root, ./scripts/build-and-push-tasky.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Config: prefer env, then terraform output
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

IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPO_NAME}/tasky:latest"

# Ensure Artifact Registry API and repository exist
if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$GCP_REGION" --project="$GCP_PROJECT_ID" &>/dev/null; then
  echo "Enabling Artifact Registry API and creating repository ${REPO_NAME}..."
  gcloud services enable artifactregistry.googleapis.com --project="$GCP_PROJECT_ID"
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$GCP_REGION" \
    --description="Tasky application container images for Wiz Exercise" \
    --project="$GCP_PROJECT_ID"
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
gcloud artifacts docker images list "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPO_NAME}" \
  --project="$GCP_PROJECT_ID" --include-tags 2>/dev/null | head -5 || true

echo "Done. Image: $IMAGE"
