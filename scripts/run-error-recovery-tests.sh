#!/usr/bin/env bash
# Run controlled error tests and recovery demos (Error Testing & Recovery Procedures ticket).
# Safely induces a failure (e.g. Terraform format), shows CI-gate failure, then restores and shows success.
#
# Usage (from repo root):
#   ./scripts/run-error-recovery-tests.sh terraform-validate   # format break → fail → restore → pass
#   ./scripts/run-error-recovery-tests.sh list                  # list available tests
#
# Requires: terraform in PATH.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

run_terraform_validate_demo() {
  # Use a small file that's easy to corrupt/restore: versions.tf is typically short.
  local target_file="${TERRAFORM_DIR}/versions.tf"
  if [[ ! -f "$target_file" ]]; then
    echo "Error: $target_file not found."
    exit 1
  fi

  local backup_file="${target_file}.run-error-recovery-bak"
  if [[ -f "$backup_file" ]]; then
    echo "Error: Previous run left backup $backup_file. Restore or remove it first."
    exit 1
  fi

  echo "=== Error test: Terraform format (terraform-validate gate) ==="
  echo ""

  cp "$target_file" "$backup_file"
  # Introduce format that fmt -check will flag: add trailing spaces (portable sed)
  if grep -q 'required_version' "$target_file"; then
    sed 's/required_version/required_version   /' "$target_file" > "${target_file}.tmp"
    mv "${target_file}.tmp" "$target_file"
  else
    echo "  # temporary format error" >> "$target_file"
  fi

  echo "1. Introduced format drift (trailing spaces or extra line)."
  echo "2. Running terraform fmt -check -recursive (expect FAIL)..."
  echo ""

  set +e
  cd "$TERRAFORM_DIR"
  terraform init -backend=false -input=false -quiet 2>/dev/null || true
  terraform fmt -check -recursive -diff
  FMT_EXIT=$?
  set -e

  if [[ $FMT_EXIT -ne 0 ]]; then
    echo ""
    echo "   -> Format check failed as expected (exit $FMT_EXIT). This would fail the CI terraform-validate job."
  else
    echo "   -> Format check passed unexpectedly; restoring and exiting."
    mv "$backup_file" "$target_file"
    exit 0
  fi

  echo ""
  echo "3. Recovering: restoring original file and re-running format check..."
  mv "$backup_file" "$target_file"
  terraform fmt -recursive -diff 2>/dev/null || true
  terraform fmt -check -recursive -diff
  echo ""
  echo "   -> Format check passed after recovery. CI gate would pass."
  echo ""
  echo "=== terraform-validate error/recovery demo complete ==="
}

list_tests() {
  echo "Available error/recovery tests:"
  echo ""
  echo "  terraform-validate   Temporarily break Terraform format, run fmt -check (fails), restore, re-run (pass)."
  echo "  security-alert      Trigger GCP detective alerts (firewall + bucket IAM). Run: ./scripts/trigger-security-alert-test.sh both"
  echo ""
  echo "See docs/ERROR_TESTING_AND_RECOVERY_PROCEDURES.md for full runbook."
}

MODE="${1:-}"
case "$MODE" in
  terraform-validate)
    run_terraform_validate_demo
    ;;
  list)
    list_tests
    ;;
  security-alert)
    echo "Run the following to trigger security alerts:"
    echo "  export GCP_PROJECT_ID=your-project-id"
    echo "  ./scripts/trigger-security-alert-test.sh both"
    echo ""
    echo "See docs/ERROR_TESTING_AND_RECOVERY_PROCEDURES.md §5."
    ;;
  *)
    echo "Usage: $0 terraform-validate | list | security-alert"
    echo ""
    list_tests
    exit 1
    ;;
esac
