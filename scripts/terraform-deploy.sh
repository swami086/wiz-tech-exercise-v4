#!/usr/bin/env bash
# Run Terraform init, plan, and apply for Wiz Technical Exercise V4.
# Prerequisites: Flow 1 complete (bootstrap, state bucket). Set env vars below.
#
# Usage (from repo root):
#   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/.keys/wiz-exercise-automation-key.json"
#   export GCP_PROJECT_ID="your-project-id"
#   ./scripts/terraform-deploy.sh
#
# Optional: set GCP_REGION for get-credentials (default us-central1).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

# Use key file if present and non-empty; otherwise use Application Default Credentials (ADC).
KEY_FILE="${REPO_ROOT}/.keys/wiz-exercise-automation-key.json"
if [[ -s "$KEY_FILE" ]]; then
  export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$KEY_FILE}"
  echo "Using key file: $GOOGLE_APPLICATION_CREDENTIALS"
else
  unset GOOGLE_APPLICATION_CREDENTIALS
  echo "Using Application Default Credentials (ADC): $HOME/.config/gcloud/application_default_credentials.json"
fi

echo "=== Terraform deploy (project: $GCP_PROJECT_ID) ==="
cd "$TERRAFORM_DIR"

# Ensure tfvars exists (MongoDB passwords required; tasky_mongodb_uri/tasky_secret_key can be left empty for derive/generate)
if [[ ! -f terraform.tfvars ]]; then
  echo "Creating terraform.tfvars from example..."
  sed "s/your-cloudlabs-project-id/${GCP_PROJECT_ID}/" terraform.tfvars.example > terraform.tfvars
  echo "  Edit terraform/terraform.tfvars: set mongodb_admin_password and mongodb_app_password (min 32 chars)."
  echo "  Leave tasky_mongodb_uri and tasky_secret_key empty for Terraform-managed MongoDB and generated JWT."
fi

BUCKET="${GCP_PROJECT_ID}-tfstate-wiz-exercise"
echo "Initializing backend (bucket: $BUCKET)..."
terraform init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="prefix=terraform/state"

echo "Planning..."
terraform plan -out=tfplan -input=false

echo "Applying..."
terraform apply -input=false tfplan

echo ""
echo "=== kubectl access ==="
echo "Run:"
echo "  gcloud container clusters get-credentials wiz-exercise-gke --region=${GCP_REGION} --project=${GCP_PROJECT_ID}"
echo "  kubectl get nodes"
echo ""
