#!/usr/bin/env bash
# Run MongoDB setup on the MongoDB VM (install MongoDB 4.4, auth, backup cron).
# Prerequisites: Terraform applied; gcloud authenticated; SSH access to VM (e.g. IAP).
#
# Usage (from repo root):
#   export GCP_PROJECT_ID="your-project-id"
#   ./scripts/run-mongodb-setup.sh <MONGO_ADMIN_PASSWORD> [MONGO_APP_PASSWORD]
#   # Or: export MONGO_ADMIN_PASSWORD=...; ./scripts/run-mongodb-setup.sh
#
# MONGO_ADMIN_PASSWORD is required (arg or env). MONGO_APP_PASSWORD is optional (default: generated).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
MONGO_ADMIN_PASSWORD="${MONGO_ADMIN_PASSWORD:-}"
MONGO_APP_PASSWORD="${MONGO_APP_PASSWORD:-}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set." >&2
  echo "  export GCP_PROJECT_ID=your-project-id" >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  MONGO_ADMIN_PASSWORD="$1"
fi
if [[ $# -ge 2 ]]; then
  MONGO_APP_PASSWORD="$2"
fi

if [[ -z "$MONGO_ADMIN_PASSWORD" ]]; then
  echo "Error: MONGO_ADMIN_PASSWORD is required (pass as first argument or set MONGO_ADMIN_PASSWORD env)." >&2
  echo "  Authentication is enforced; provide a strong admin password." >&2
  exit 1
fi

cd "$TERRAFORM_DIR"
BUCKET=$(terraform output -raw mongodb_backup_bucket)
VM_NAME=$(terraform output -raw mongodb_vm_name)
ZONE=$(terraform output -raw mongodb_vm_zone)

echo "VM: $VM_NAME  Zone: $ZONE  Backup bucket: $BUCKET"
echo "Copying mongodb-install.sh to VM..."
gcloud compute scp "$REPO_ROOT/scripts/mongodb-install.sh" "${VM_NAME}:~/mongodb-install.sh" \
  --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap --internal-ip

if [[ -n "$MONGO_APP_PASSWORD" ]]; then
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap --internal-ip -- \
    "sudo bash ~/mongodb-install.sh '$BUCKET' '$MONGO_ADMIN_PASSWORD' '$MONGO_APP_PASSWORD'"
else
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap --internal-ip -- \
    "sudo bash ~/mongodb-install.sh '$BUCKET' '$MONGO_ADMIN_PASSWORD'"
fi

echo "Done. See docs/MONGODB_SETUP_AND_BACKUP.md for verification, app user, and MONGO_URI."
