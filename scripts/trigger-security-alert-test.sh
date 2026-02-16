#!/usr/bin/env bash
# Trigger security-relevant events to test detective controls (GCP Security Tooling).
# Run one or both: firewall update (triggers firewall-change alert), bucket IAM get+set (triggers bucket IAM alert).
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./scripts/trigger-security-alert-test.sh [firewall|bucket|both]

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
FIREWALL_NAME="${FIREWALL_NAME:-wiz-exercise-allow-ssh-vm}"
BUCKET_NAME="${BUCKET_NAME:-}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  exit 1
fi

case "${1:-both}" in
  firewall)
    echo "Updating firewall rule $FIREWALL_NAME to trigger [Wiz Exercise] Firewall rule create/update/delete alert..."
    gcloud compute firewall-rules update "$FIREWALL_NAME" \
      --project="$GCP_PROJECT_ID" \
      --description="Wiz-exercise-SSH-to-VM-triggered-$(date +%Y%m%d-%H%M)" \
      --quiet
    echo "Done. Check Monitoring → Alerting → Incidents in a few minutes."
    ;;
  bucket)
    if [[ -z "$BUCKET_NAME" ]]; then
      BUCKET_NAME="${GCP_PROJECT_ID}-mongodb-backups-wiz-exercise"
    fi
    if ! gsutil ls "gs://${BUCKET_NAME}/" &>/dev/null; then
      echo "Error: Bucket gs://${BUCKET_NAME} does not exist or is not accessible. Create it (e.g. via Terraform) before triggering the bucket IAM alert."
      exit 1
    fi
    echo "Getting then setting IAM on gs://$BUCKET_NAME to trigger [Wiz Exercise] Storage bucket IAM change alert..."
    TEMP=$(mktemp)
    trap 'rm -f "$TEMP"' EXIT
    gsutil iam get "gs://${BUCKET_NAME}" > "$TEMP"
    gsutil iam set "$TEMP" "gs://${BUCKET_NAME}"
    echo "Done. Check Monitoring → Alerting → Incidents in a few minutes."
    ;;
  both)
    "$0" firewall
    "$0" bucket
    ;;
  *)
    echo "Usage: $0 [firewall|bucket|both]"
    exit 1
    ;;
esac
