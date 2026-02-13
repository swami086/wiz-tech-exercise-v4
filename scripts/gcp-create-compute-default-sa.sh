#!/usr/bin/env bash
# Create a custom "compute-default" service account with Editor role.
# Use when the project does not have the system default compute SA
# (PROJECT_NUMBER-compute@developer.gserviceaccount.com).
#
# Note: GKE cluster creation still requires the system default SA; this script
# only provides a replacement for VMs and other workloads.
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./scripts/gcp-create-compute-default-sa.sh

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
SA_NAME="${SA_NAME:-compute-default}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  exit 1
fi

SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" &>/dev/null; then
  echo "Service account $SA_EMAIL already exists."
else
  echo "Creating service account $SA_NAME..."
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$GCP_PROJECT_ID" \
    --display-name="Compute Engine default (replacement)" \
    --description="Replacement for missing default compute SA; Editor role for VM/compute workloads."
fi

echo "Granting roles/editor..."
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor" \
  --quiet

echo ""
echo "Done. Service account: $SA_EMAIL"
