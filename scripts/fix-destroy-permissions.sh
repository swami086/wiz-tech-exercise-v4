#!/usr/bin/env bash
# Fix Terraform destroy permissions for the automation service account.
# Destroy failed with: artifactregistry.repositories.delete denied, iam.serviceAccounts.delete denied.
#
# Run with: export GCP_PROJECT_ID=your-project && ./scripts/fix-destroy-permissions.sh
# Or:        ./scripts/fix-destroy-permissions.sh  (uses wizdemo-487311 if unset)

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-wizdemo-487311}"
SA_NAME="${SA_NAME:-wiz-exercise-automation}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Fix destroy permissions ==="
echo "  Project: $GCP_PROJECT_ID"
echo "  SA:      $SA_EMAIL"
echo ""

gcloud config set project "$GCP_PROJECT_ID"

echo "Granting roles/artifactregistry.admin (allows delete Artifact Registry repos)..."
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.admin" \
  --condition=None \
  --quiet

echo "Granting roles/iam.serviceAccountAdmin (allows delete GKE/MongoDB SAs)..."
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountAdmin" \
  --condition=None \
  --quiet

echo "Granting roles/serviceusage.serviceUsageAdmin (allows disable APIs on destroy)..."
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/serviceusage.serviceUsageAdmin" \
  --condition=None \
  --quiet

echo "Done. Re-run the IaC Destroy workflow (Actions → IaC Destroy → Run workflow)."
echo "If you see 'subnetwork already in use', wait 2–3 min for GKE/VM to finish deleting, then run Destroy again."