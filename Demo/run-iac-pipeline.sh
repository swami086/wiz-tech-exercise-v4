#!/usr/bin/env bash
# Run the IaC Deploy pipeline (trigger in GitHub or run steps locally).
#
# Use this when you create or change infrastructure with Terraform:
# - Trigger the GitHub Actions workflow "IaC Deploy" (iac-deploy.yml), or
# - Run the same validate (and optionally apply) steps locally.
#
# Usage (from repo root):
#   ./Demo/run-iac-pipeline.sh                    # trigger workflow on current branch
#   ./Demo/run-iac-pipeline.sh --ref main         # trigger workflow on main
#   ./Demo/run-iac-pipeline.sh --local            # run validate only locally (no apply)
#   ./Demo/run-iac-pipeline.sh --local --apply    # run validate + plan + apply locally
#
# Trigger: requires gh CLI (gh auth login). Local: requires terraform, optional docker (tfsec).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
WORKFLOW_NAME="IaC Deploy"

TRIGGER_MODE=true
LOCAL_MODE=false
APPLY_LOCAL=false
REF=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL_MODE=true
      TRIGGER_MODE=false
      shift
      ;;
    --apply)
      APPLY_LOCAL=true
      shift
      ;;
    --ref)
      REF="${2:?Usage: --ref <branch>}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1. Usage: $0 [--local] [--apply] [--ref BRANCH]"
      exit 1
      ;;
  esac
done
# For trigger: ref flag for gh workflow run
if [[ -n "${REF:-}" ]]; then
  REF_FLAG="--ref $REF"
else
  REF_FLAG=""
fi

blue='\033[0;34m'
bold='\033[1m'
nc='\033[0m'
section() { echo ""; echo -e "${blue}${bold}=== $* ===${nc}"; }

# -----------------------------------------------------------------------------
# Trigger GitHub Actions workflow
# -----------------------------------------------------------------------------
trigger_workflow() {
  command -v gh &>/dev/null || { echo "Error: gh CLI required. Install and run 'gh auth login'."; exit 1; }
  cd "$REPO_ROOT"
  if [[ -z "$REF_FLAG" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true
    REF_FLAG="${BRANCH:+--ref $BRANCH}"
  fi
  section "Triggering workflow: $WORKFLOW_NAME"
  echo "Workflow: $WORKFLOW_NAME (iac-deploy.yml)"
  echo "Ref: ${REF_FLAG:-default branch}"
  gh workflow run "iac-deploy.yml" $REF_FLAG
  echo ""
  echo "Workflow triggered. View runs: gh run list --workflow=iac-deploy.yml"
  echo "Or: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/workflows/iac-deploy.yml"
}

# -----------------------------------------------------------------------------
# Run validate locally (same as workflow validate job)
# -----------------------------------------------------------------------------
run_validate_local() {
  section "Validate (local – same as IaC pipeline)"
  cd "$TF_DIR"
  echo "Terraform Init (no backend)..."
  terraform init -backend=false -input=false
  echo "Terraform Validate..."
  terraform validate
  echo "Terraform Format Check..."
  terraform fmt -check -recursive -diff
  echo "IaC security scan (tfsec)..."
  if command -v docker &>/dev/null; then
    docker run --rm -v "$REPO_ROOT:/src" aquasec/tfsec:latest /src/terraform --minimum-severity HIGH --no-color 2>/dev/null || true
  else
    echo "  (skipped – docker not available)"
  fi
  echo ""
  echo "Validate OK."
}

# -----------------------------------------------------------------------------
# Run plan + apply locally (same as workflow deploy job)
# -----------------------------------------------------------------------------
run_apply_local() {
  section "Plan and Apply (local)"
  cd "$TF_DIR"
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(terraform output -raw project_id 2>/dev/null || true)}"
  TF_STATE_BUCKET="${TF_STATE_BUCKET:-${GCP_PROJECT_ID}-tfstate-wiz-exercise}"
  if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
    echo "Error: GCP_PROJECT_ID not set and terraform output project_id empty. Set GCP_PROJECT_ID or run from a state that has project_id."
    exit 1
  fi
  echo "State bucket: $TF_STATE_BUCKET (set TF_STATE_BUCKET to override)"
  echo "Terraform Init (GCS backend)..."
  terraform init -input=false \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="prefix=terraform/state"
  echo "Terraform Plan..."
  terraform plan -input=false -out=tfplan
  echo "Terraform Apply..."
  terraform apply -input=false -auto-approve tfplan
  echo ""
  echo "Apply OK."
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
if [[ "$LOCAL_MODE" == "true" ]]; then
  run_validate_local
  if [[ "$APPLY_LOCAL" == "true" ]]; then
    run_apply_local
  else
    echo ""
    echo "To run plan + apply locally: ./Demo/run-iac-pipeline.sh --local --apply"
  fi
else
  trigger_workflow
fi
