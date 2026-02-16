#!/usr/bin/env bash
# Enable Security Command Center (SCC) Standard tier for the project.
# SCC Standard is required for the GCP Security Tooling ticket; activation
# is done via Console (no stable gcloud command for project-level Standard).
#
# This script ensures the API is enabled and prints activation steps.
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./scripts/enable-scc-standard.sh

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

echo "=== Security Command Center (SCC) Standard tier ==="
echo "  Project: $GCP_PROJECT_ID"
echo ""

# Ensure Security Command Center API is enabled
echo "Enabling securitycenter.googleapis.com..."
gcloud services enable securitycenter.googleapis.com --project="$GCP_PROJECT_ID"

echo ""
echo "SCC Standard tier must be activated in the Google Cloud Console:"
echo "  1. Open: https://console.cloud.google.com/security/command-center?project=${GCP_PROJECT_ID}"
echo "  2. If prompted, choose 'Get started' or 'Enable Security Command Center'."
echo "  3. Select the 'Standard' tier (no cost) and activate for this project."
echo "  4. After activation, enable all available detectors:"
echo "     - Security Health Analytics"
echo "     - Web Security Scanner (if available)"
echo "  5. Wait for the initial scan to complete (may take several minutes)."
echo ""
echo "Then review findings under Security Command Center → Findings."
echo "See docs/GCP_SECURITY_TOOLING.md for SCC review and security posture steps."
