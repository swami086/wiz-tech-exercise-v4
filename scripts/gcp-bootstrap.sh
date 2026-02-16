#!/usr/bin/env bash
# GCP Bootstrap for Wiz Technical Exercise V4
# Enables required APIs, creates automation service account, and Terraform state GCS bucket.
# Prerequisites: gcloud CLI installed and authenticated (gcloud auth login).
#
# Usage:
#   export GCP_PROJECT_ID=your-cloudlabs-project-id
#   export GCP_REGION=us-central1
#   ./scripts/gcp-bootstrap.sh

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
SA_NAME="${SA_NAME:-wiz-exercise-automation}"
SA_DISPLAY_NAME="Wiz Exercise Automation (Terraform/CI)"
BUCKET_NAME="${TF_STATE_BUCKET:-}"
KEY_DIR="${KEY_DIR:-./.keys}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set. Export it or pass the project ID."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

# Terraform state bucket: must be globally unique; default to project-prefixed name
if [[ -z "$BUCKET_NAME" ]]; then
  BUCKET_NAME="${GCP_PROJECT_ID}-tfstate-wiz-exercise"
fi

echo "=== GCP Bootstrap ==="
echo "  Project: $GCP_PROJECT_ID"
echo "  Region:  $GCP_REGION"
echo "  SA:      $SA_NAME"
echo "  Bucket:  $BUCKET_NAME"
echo ""

# Set project
gcloud config set project "$GCP_PROJECT_ID"

# Enable required APIs (Compute, GKE, Storage, Logging, SCC, Monitoring for alert policies)
echo "Enabling APIs..."
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  storage.googleapis.com \
  storage-api.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  securitycenter.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="$GCP_PROJECT_ID"

# Create service account for automation (Terraform / CI)
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" &>/dev/null; then
  echo "Service account $SA_EMAIL already exists."
else
  echo "Creating service account $SA_NAME..."
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="$SA_DISPLAY_NAME" \
    --project="$GCP_PROJECT_ID"
fi

# Grant roles needed for Terraform (VPC, GKE, Compute VM, GCS, IAM, Logging, SCC, Monitoring alerts)
# projectIamAdmin required to create IAM bindings (e.g. for MongoDB VM SA).
# monitoring.alertPolicyEditor required for GCP Security Tooling alert policies.
echo "Granting IAM roles to service account..."
for role in \
  roles/compute.admin \
  roles/container.admin \
  roles/storage.admin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/logging.configWriter \
  roles/securitycenter.admin \
  roles/monitoring.alertPolicyEditor \
  roles/monitoring.notificationChannelEditor; do
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --condition=None \
    --quiet
done

# Create GCS bucket for Terraform state with versioning
echo "Creating Terraform state bucket..."
if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
  echo "Bucket gs://${BUCKET_NAME} already exists."
else
  gsutil mb -p "$GCP_PROJECT_ID" -l "$GCP_REGION" "gs://${BUCKET_NAME}"
fi
gsutil versioning set on "gs://${BUCKET_NAME}"

# Allow the service account to read/write the state bucket
gsutil iam ch "serviceAccount:${SA_EMAIL}:objectAdmin" "gs://${BUCKET_NAME}"

# Download service account key (store securely; do not commit)
mkdir -p "$KEY_DIR"
KEY_FILE="${KEY_DIR}/${SA_NAME}-key.json"
echo "Creating key and saving to ${KEY_FILE} (ensure this path is in .gitignore)..."
gcloud iam service-accounts keys create "$KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$GCP_PROJECT_ID"

echo ""
echo "=== Bootstrap complete ==="
echo "  Service account: $SA_EMAIL"
echo "  Key file:        $KEY_FILE"
echo "  State bucket:    gs://${BUCKET_NAME} (versioning on)"
echo ""
echo "Next steps:"
echo "  1. Store $KEY_FILE securely (e.g. GitHub Secrets for CI). Do not commit it."
echo "  2. Use bucket name '$BUCKET_NAME' in Terraform backend config."
echo "  3. For local Terraform: export GOOGLE_APPLICATION_CREDENTIALS=$KEY_FILE"
echo ""
