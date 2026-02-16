#!/usr/bin/env bash
# Structured end-to-end demo for the CI/CD flow (Wiz Technical Exercise).
# Runs: pre-requisites → local CI gate simulation → optional GitHub Actions demo → deployment verification.
#
# Usage (from repo root):
#   ./scripts/demo-cicd-end-to-end.sh                    # full demo (local gates + optional GitHub + verify)
#   SKIP_GITHUB_DEMO=1 ./scripts/demo-cicd-end-to-end.sh # skip GitHub (PR/workflow) section
#   RUN_LOCAL_GATES_ONLY=1 ./scripts/demo-cicd-end-to-end.sh  # only run local CI gate simulation; exit after
#
# Env:
#   GCP_PROJECT_ID     - GCP project (default: from terraform output)
#   SKIP_GITHUB_DEMO   - 1 to skip Phase 2 (GitHub branch protection / workflow demo)
#   RUN_LOCAL_GATES_ONLY - 1 to run only Phase 0 + Phase 1 and exit (no deploy verification)
#   SKIP_BUILD_PUSH    - 1 to skip build-and-push before Phase 3 (use existing image)
#   GH_TOKEN           - Optional; for gh CLI when running GitHub demo (or use gh auth login)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- Config from env ---
SKIP_GITHUB_DEMO="${SKIP_GITHUB_DEMO:-0}"
RUN_LOCAL_GATES_ONLY="${RUN_LOCAL_GATES_ONLY:-0}"
SKIP_BUILD_PUSH="${SKIP_BUILD_PUSH:-0}"

if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
  if command -v terraform &>/dev/null && [[ -d "$REPO_ROOT/terraform" ]]; then
    GCP_PROJECT_ID=$(cd "$REPO_ROOT/terraform" && terraform output -raw project_id 2>/dev/null || true)
  fi
fi

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
nc='\033[0m'

section() { echo ""; echo -e "${blue}=== $* ===${nc}"; }
ok()    { echo -e "${green}OK: $*${nc}"; }
warn()  { echo -e "${yellow}WARN: $*${nc}"; }
fail()  { echo -e "${red}FAIL: $*${nc}"; exit 1; }

# -----------------------------------------------------------------------------
# Phase 0: Prerequisites
# -----------------------------------------------------------------------------
section "Phase 0: Prerequisites"

command -v gcloud &>/dev/null || fail "gcloud not found; install Google Cloud SDK."
command -v docker &>/dev/null || fail "docker not found; install Docker."
command -v terraform &>/dev/null || fail "terraform not found; install Terraform (>= 1.5.0)."
command -v kubectl &>/dev/null || warn "kubectl not found; Phase 3 (deployment verification) may fail."

[[ -n "${GCP_PROJECT_ID:-}" ]] || fail "GCP_PROJECT_ID not set and could not get from terraform output. Export GCP_PROJECT_ID."
ok "GCP_PROJECT_ID=$GCP_PROJECT_ID"

# Optional for Phase 2
if [[ "$SKIP_GITHUB_DEMO" != "1" ]]; then
  if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then
      ok "gh CLI authenticated"
    else
      warn "gh not authenticated; run 'gh auth login' or set GH_TOKEN for Phase 2."
    fi
  else
    warn "gh CLI not found; Phase 2 (GitHub demo) will be skipped. Install gh to run GitHub steps."
    SKIP_GITHUB_DEMO=1
  fi
fi

# -----------------------------------------------------------------------------
# Phase 1: Local CI gate simulation (mirrors GitHub Actions)
# -----------------------------------------------------------------------------
section "Phase 1: Local CI gate simulation (terraform-validate, container-scan, deploy build/verify)"

# 1a. Terraform validate (mirrors .github/workflows/terraform-validate.yml)
section "Phase 1a: Terraform validate"
(cd "$REPO_ROOT/terraform" && terraform init -backend=false) || fail "terraform init -backend=false failed."
(cd "$REPO_ROOT/terraform" && terraform validate) || fail "terraform validate failed."
(cd "$REPO_ROOT/terraform" && terraform fmt -check -recursive -diff) || fail "terraform fmt check failed (run: terraform fmt -recursive)."
ok "Terraform validate and format check passed."

# 1b. Container build + Trivy (mirrors .github/workflows/container-scan.yml)
section "Phase 1b: Container build and Trivy scan"
TASKY_IMAGE_LOCAL="tasky:local-demo"
docker build --platform linux/amd64 -t "$TASKY_IMAGE_LOCAL" ./tasky-main || fail "Docker build failed."
docker run --rm --platform linux/amd64 --entrypoint cat "$TASKY_IMAGE_LOCAL" /app/wizexercise.txt | grep -q . || fail "wizexercise.txt missing in image."
ok "Image built and wizexercise.txt present."

if command -v trivy &>/dev/null; then
  if trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed "$TASKY_IMAGE_LOCAL" 2>/dev/null; then
    ok "Trivy scan passed (no CRITICAL/HIGH)."
  else
    warn "Trivy found CRITICAL/HIGH (or trivy failed). Pipeline would fail; fix or ignore for demo."
  fi
else
  warn "trivy not installed; skipping container scan (install for full gate simulation)."
fi

# 1c. Deploy job simulation: build + verify only (no push in local simulation)
section "Phase 1c: Deploy job (build + verify only, no push)"
ok "Deploy gate simulated: image build and wizexercise.txt check passed (push happens on push to main in CI)."

if [[ "$RUN_LOCAL_GATES_ONLY" == "1" ]]; then
  echo ""
  echo -e "${green}=== RUN_LOCAL_GATES_ONLY=1: stopping after Phase 1 ===${nc}"
  echo "To run full demo: unset RUN_LOCAL_GATES_ONLY and run again."
  exit 0
fi

# -----------------------------------------------------------------------------
# Phase 2: GitHub Actions demo (optional)
# -----------------------------------------------------------------------------
if [[ "$SKIP_GITHUB_DEMO" != "1" ]] && command -v gh &>/dev/null; then
  section "Phase 2: GitHub branch protection and status checks"

  if gh auth status &>/dev/null; then
    echo "Current required status checks for main:"
    "$REPO_ROOT/scripts/github-require-status-checks.sh" 2>/dev/null || true
    echo ""
    echo "To enforce terraform-validate, container-scan, deploy before merge, run:"
    echo "  ./scripts/github-require-status-checks.sh terraform-validate container-scan deploy"
    echo ""
    echo "To trigger workflows manually: GitHub → Actions → select workflow → Run workflow."
    ok "GitHub CLI ready; use Actions UI or create a PR to demonstrate pipeline runs."
  else
    warn "gh not authenticated; skipping Phase 2."
  fi
else
  section "Phase 2: Skipped (SKIP_GITHUB_DEMO=1 or gh not available)"
fi

# -----------------------------------------------------------------------------
# Phase 3: Build, push, and deployment verification
# -----------------------------------------------------------------------------
section "Phase 3: Build, push, and deployment verification"

if [[ "$SKIP_BUILD_PUSH" != "1" ]]; then
  echo "Building and pushing Tasky image to Artifact Registry..."
  GCP_PROJECT_ID="$GCP_PROJECT_ID" "$REPO_ROOT/scripts/build-and-push-tasky.sh" || fail "build-and-push-tasky.sh failed."
else
  echo "SKIP_BUILD_PUSH=1: using existing image in Artifact Registry."
fi

echo "Running deployment verification (rollout restart, pods, LB, wizexercise.txt, cluster-admin)..."
GCP_PROJECT_ID="$GCP_PROJECT_ID" "$REPO_ROOT/scripts/verify-tasky-deployment.sh" || fail "verify-tasky-deployment.sh failed."

section "Demo complete"
echo "Next: open the Load Balancer IP in a browser and demonstrate CRUD + persistence."
echo "See docs/DEMO_EXECUTION_AND_PRESENTATION_RUNBOOK.md for presentation narrative."
