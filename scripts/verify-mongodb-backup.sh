#!/usr/bin/env bash
# Verify MongoDB backup cron on the VM and optionally run a backup now.
# Requires: gcloud auth (gcloud auth login), project set (gcloud config set project PROJECT_ID).
# Usage: ./scripts/verify-mongodb-backup.sh [PROJECT_ID]
# Example: ./scripts/verify-mongodb-backup.sh wizdemo-487311

set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET="${PROJECT_ID}-mongodb-backups-wiz-exercise"
VM_NAME="wiz-exercise-mongodb"
ZONE="${ZONE:-us-central1-a}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 PROJECT_ID   (e.g. wizdemo-487311)"
  exit 1
fi

echo "=== 1. List GCS backup bucket (should show gs://$BUCKET/daily/...) ==="
gcloud storage ls "gs://${BUCKET}/" 2>/dev/null || { echo "Bucket empty or not found. Run backup on VM."; }

echo ""
echo "=== 2. Find MongoDB VM ==="
gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM_NAME" --format="table(name,zone,status)" 2>/dev/null || true

echo ""
echo "=== 3. SSH to VM and check cron + run backup (IAP tunnel) ==="
echo "Run these commands (copy-paste) after 'gcloud auth login' and 'gcloud config set project $PROJECT_ID':"
echo ""
echo "  # SSH into the VM (use IAP if no external IP)"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID --tunnel-through-iap"
echo ""
echo "  # On the VM: check cron and backup log"
echo "  sudo crontab -l"
echo "  sudo cat /var/log/mongodb-backup.log"
echo ""
echo "  # On the VM: run backup now"
echo "  sudo /usr/local/bin/mongodb-backup-to-gcs.sh"
echo ""
echo "  # Then list bucket again from your machine"
echo "  gcloud storage ls gs://$BUCKET/daily/"
echo ""
