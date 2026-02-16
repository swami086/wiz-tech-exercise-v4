#!/usr/bin/env bash
# Terraform validate, plan, destroy, and recreate – Wiz Technical Exercise V4
#
# Full lifecycle: validate → plan (current) → destroy → plan (recreate) → apply.
# Use this to prove infrastructure is reproducible after destroy.
#
# Usage (from repo root):
#   ./Demo/terraform-destroy-recreate.sh              # full cycle + optional showcase at end
#   ./Demo/terraform-destroy-recreate.sh --no-destroy # validate + plan only (no destroy/apply)
#   ./Demo/terraform-destroy-recreate.sh --skip-showcase  # full cycle, skip IaC showcase at end
#   ./Demo/terraform-destroy-recreate.sh --yes            # full cycle without destroy confirmation
#
# Requires: terraform, valid terraform.tfvars (or -var) for project_id, etc.
# Optional: gcloud, kubectl (for showcase); ensure GCP project and credentials are set.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
PLAN_FILE="$TF_DIR/tfplan"

NO_DESTROY=false
SKIP_SHOWCASE=false
CONFIRM_YES=false
for arg in "$@"; do
  if [[ "$arg" == "--no-destroy" ]]; then
    NO_DESTROY=true
  elif [[ "$arg" == "--skip-showcase" ]]; then
    SKIP_SHOWCASE=true
  elif [[ "$arg" == "--yes" ]] || [[ "$arg" == "-y" ]]; then
    CONFIRM_YES=true
  fi
done

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
bold='\033[1m'
nc='\033[0m'
section() { echo ""; echo -e "${blue}${bold}=== $* ===${nc}"; }
ok() { echo -e "${green}$*${nc}"; }
warn() { echo -e "${yellow}$*${nc}"; }
die() { echo -e "${red}Error: $*${nc}"; exit 1; }

cd "$TF_DIR"

# -----------------------------------------------------------------------------
# 1. Init
# -----------------------------------------------------------------------------
section "1. Terraform init"
terraform init -input=false
ok "Init OK"

# -----------------------------------------------------------------------------
# 2. Validate
# -----------------------------------------------------------------------------
section "2. Terraform validate"
terraform validate
ok "Validate OK"

# -----------------------------------------------------------------------------
# 3. Plan (current state)
# -----------------------------------------------------------------------------
section "3. Terraform plan (current state)"
set +e
terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE"
# exit code 0 = no changes, 1 = error, 2 = changes present
PLAN_EXIT=$?
set -e
if [[ $PLAN_EXIT -eq 1 ]]; then
  die "Terraform plan failed."
fi
if [[ $PLAN_EXIT -eq 0 ]]; then
  ok "Plan: no changes (environment matches config)."
else
  ok "Plan: changes detected (saved to $PLAN_FILE)."
fi

if [[ "$NO_DESTROY" == "true" ]]; then
  section "Done (--no-destroy)"
  echo "Skipping destroy and apply. Run without --no-destroy to run full destroy/recreate."
  exit 0
fi

# -----------------------------------------------------------------------------
# 4. Destroy (with confirmation unless --yes)
# -----------------------------------------------------------------------------
section "4. Terraform destroy"
if [[ "$CONFIRM_YES" != "true" ]]; then
  echo "This will DESTROY all Terraform-managed infrastructure (GKE, VM, bucket, etc.)."
  echo -n "Type 'yes' to continue: "
  read -r CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi
echo "Destroying all managed infrastructure (this may take several minutes)..."
terraform destroy -auto-approve -input=false
ok "Destroy complete."

# -----------------------------------------------------------------------------
# 5. Plan (recreate)
# -----------------------------------------------------------------------------
section "5. Terraform plan (recreate)"
terraform plan -input=false -out="$PLAN_FILE"
ok "Plan for recreate saved."

# -----------------------------------------------------------------------------
# 6. Apply (recreate)
# -----------------------------------------------------------------------------
section "6. Terraform apply (recreate)"
echo "Applying configuration to recreate environment..."
terraform apply -auto-approve -input=false
ok "Apply complete."

# -----------------------------------------------------------------------------
# 7. Optional: IaC showcase
# -----------------------------------------------------------------------------
if [[ "$SKIP_SHOWCASE" != "true" ]]; then
  section "7. IaC requirements showcase (validation)"
  if [[ -x "$REPO_ROOT/Demo/showcase-iac-requirements.sh" ]]; then
    "$REPO_ROOT/Demo/showcase-iac-requirements.sh" || warn "Showcase script reported issues (see above)."
  else
    warn "Showcase script not found or not executable; skipping."
  fi
else
  section "Done (--skip-showcase)"
  echo "Skipped IaC showcase. Run: ./Demo/showcase-iac-requirements.sh"
fi

section "Terraform destroy/recreate complete"
echo "Environment was destroyed and recreated successfully."
echo "  --no-destroy     validate + plan only (no destroy/apply)"
echo "  --skip-showcase  do not run showcase-iac-requirements.sh after apply"
echo "  --yes / -y       skip confirmation prompt before destroy"
