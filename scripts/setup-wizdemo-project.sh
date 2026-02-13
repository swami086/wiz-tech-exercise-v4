#!/usr/bin/env bash
# Set up the GCP project wizdemo-487311 for the Wiz exercise:
# - Authenticate and set project
# - Run bootstrap (APIs, automation SA, state bucket, key in .keys)
# - Check for default Compute Engine SA (required for GKE)
#
# Prerequisites:
#   1. Run in a terminal (interactive login required):
#        gcloud auth login
#      Sign in with the account that has access to wizdemo-487311
#      (e.g. the account you use in Cloud Console for that project.)
#   2. Then run this script from the repo root.
#
# Keys are written to: .keys/wiz-exercise-automation-key.json
# (Back up .keys/ from another project first if you need to keep both.)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT_ID="wizdemo-487311"
KEY_DIR="${KEY_DIR:-$REPO_ROOT/.keys}"

echo "=== Setup project: $PROJECT_ID ==="
echo ""

# Use current gcloud account; ensure project is set
gcloud config set project "$PROJECT_ID"
echo "Active account: $(gcloud config get-value account)"
echo ""

# Verify access
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  echo "Error: Current account does not have access to project $PROJECT_ID."
  echo "Run: gcloud auth login"
  echo "Then sign in with the account that owns $PROJECT_ID and run this script again."
  exit 1
fi

# Check for default Compute Engine SA (GKE needs it)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
DEFAULT_COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
if gcloud iam service-accounts describe "$DEFAULT_COMPUTE_SA" --project="$PROJECT_ID" &>/dev/null; then
  echo "Default Compute Engine SA exists: $DEFAULT_COMPUTE_SA"
  echo "GKE cluster creation should work."
else
  echo "Note: Default Compute Engine SA ($DEFAULT_COMPUTE_SA) not found."
  echo "GKE may fail with 'failed to check status for ...-compute@developer.gserviceaccount.com'."
  echo "This project may still be usable for other resources."
fi
echo ""

# Bootstrap: APIs, automation SA, state bucket, key
export GCP_PROJECT_ID="$PROJECT_ID"
export KEY_DIR="$KEY_DIR"
./scripts/gcp-bootstrap.sh

echo ""
echo "=== Next steps ==="
echo "1. Use this project for Terraform:"
echo "   export GCP_PROJECT_ID=$PROJECT_ID"
echo "   export GOOGLE_APPLICATION_CREDENTIALS=\"$KEY_DIR/wiz-exercise-automation-key.json\""
echo ""
echo "2. Update terraform/terraform.tfvars: set project_id = \"$PROJECT_ID\""
echo ""
echo "3. Deploy infrastructure:"
echo "   ./scripts/terraform-deploy.sh"
echo ""
