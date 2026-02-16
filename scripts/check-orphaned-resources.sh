#!/usr/bin/env bash
# List billable GCP resources that may be left over after terraform destroy.
# Exits non-zero if any such resources are found (so CI or runbooks can fail on orphans).
# Run after: cd terraform && terraform destroy
# See docs/INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md (Cost control and orphan check).
#
# Usage (from repo root):
#   export GCP_PROJECT_ID="your-project-id"
#   ./scripts/check-orphaned-resources.sh

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
STATE_BUCKET_SUFFIX="-tfstate-wiz-exercise"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

FAILED=0

echo "=== Orphaned resources check (project: $GCP_PROJECT_ID) ==="
echo "Run this after 'terraform destroy' to find leftover billable resources."
echo ""

# GKE clusters
echo "--- GKE clusters ---"
GKE=$(gcloud container clusters list --project="$GCP_PROJECT_ID" --format="value(name)" 2>/dev/null || true)
if [[ -n "$GKE" ]]; then
  echo "$GKE"
  ((FAILED++)) || true
else
  echo "(none)"
fi

# GCE instances
echo ""
echo "--- GCE instances ---"
VM=$(gcloud compute instances list --project="$GCP_PROJECT_ID" --format="value(name)" 2>/dev/null || true)
if [[ -n "$VM" ]]; then
  echo "$VM"
  ((FAILED++)) || true
else
  echo "(none)"
fi

# Disks
echo ""
echo "--- Compute disks ---"
DISKS=$(gcloud compute disks list --project="$GCP_PROJECT_ID" --format="value(name,zone)" 2>/dev/null || true)
if [[ -n "$DISKS" ]]; then
  echo "$DISKS"
  ((FAILED++)) || true
else
  echo "(none)"
fi

# Reserved IP addresses
echo ""
echo "--- Reserved IP addresses ---"
IPS=$(gcloud compute addresses list --project="$GCP_PROJECT_ID" --format="value(name,region)" 2>/dev/null || true)
if [[ -n "$IPS" ]]; then
  echo "$IPS"
  ((FAILED++)) || true
else
  echo "(none)"
fi

# GCS buckets (exclude Terraform state bucket – not managed by this Terraform config)
echo ""
echo "--- GCS buckets (excluding state bucket *${STATE_BUCKET_SUFFIX}) ---"
BUCKETS=""
if gcloud storage buckets list --project="$GCP_PROJECT_ID" --format="value(name)" &>/dev/null; then
  BUCKETS=$(gcloud storage buckets list --project="$GCP_PROJECT_ID" --format="value(name)" 2>/dev/null || true)
else
  BUCKETS=$(gsutil ls -p "$GCP_PROJECT_ID" 2>/dev/null | sed -n 's|gs://\([^/]*\)/.*|\1|p' | sort -u || true)
fi
ORPHAN_BUCKETS=""
if [[ -n "$BUCKETS" ]]; then
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    if [[ "$b" != *"${STATE_BUCKET_SUFFIX}" ]]; then
      ORPHAN_BUCKETS="${ORPHAN_BUCKETS}${b}\n"
    fi
  done <<< "$BUCKETS"
fi
if [[ -n "$ORPHAN_BUCKETS" ]]; then
  echo -e "$ORPHAN_BUCKETS"
  ((FAILED++)) || true
else
  echo "(none)"
fi

# Artifact Registry repositories (--location required; use default region)
echo ""
echo "--- Artifact Registry repositories ---"
AR_LOCATION="${AR_LOCATION:-us-central1}"
AR=$(gcloud artifacts repositories list --location="$AR_LOCATION" --project="$GCP_PROJECT_ID" --format="value(name)")
if [[ -n "$AR" ]]; then
  echo "$AR"
  ((FAILED++)) || true
else
  echo "(none)"
fi

echo ""
if [[ $FAILED -gt 0 ]]; then
  echo "Result: $FAILED resource type(s) have leftover resources. Delete them to avoid ongoing cost (see docs for teardown steps)."
  exit 1
fi
echo "Result: No orphaned billable resources found."
exit 0
