#!/usr/bin/env bash
# Update branch protection on main to require specific status checks (CI/CD job names).
# Run from repo root. Uses gh CLI (must be authenticated: gh auth login).
#
# Usage:
#   # Show current required status checks (GET only; no PUT)
#   ./scripts/github-require-status-checks.sh
#
#   # Set required checks (PUT only when at least one check name is given)
#   ./scripts/github-require-status-checks.sh "terraform-validate" "container-scan" "deploy"
#
#   # Or pass via env (comma-separated)
#   REQUIRED_CHECKS="terraform-validate,container-scan,deploy" ./scripts/github-require-status-checks.sh

set -euo pipefail

BRANCH="${BRANCH:-main}"
CONTEXTS=()

if [[ $# -gt 0 ]]; then
  for c in "$@"; do
    CONTEXTS+=("$c")
  done
elif [[ -n "${REQUIRED_CHECKS:-}" ]]; then
  IFS=',' read -ra CONTEXTS <<< "$REQUIRED_CHECKS"
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# No check names: only GET and print current required checks; do not PUT.
if [[ ${#CONTEXTS[@]} -eq 0 ]]; then
  echo "Current required status checks for $REPO (branch: $BRANCH):"
  CURRENT=$(gh api "repos/$REPO/branches/$BRANCH/protection" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -q '.required_status_checks.contexts' 2>/dev/null || echo "[]")
  if [[ "$CURRENT" == "[]" || -z "$CURRENT" ]]; then
    echo "  (none)"
  else
    echo "$CURRENT" | jq -r '.[]' | sed 's/^/  /'
  fi
  echo ""
  echo "To set required checks, pass at least one check name: $0 <job-name-1> [job-name-2] ..."
  exit 0
fi

# At least one context: build JSON and PUT.
CONTEXTS_JSON="["
for i in "${!CONTEXTS[@]}"; do
  [[ $i -gt 0 ]] && CONTEXTS_JSON+=","
  CONTEXTS_JSON+="\"${CONTEXTS[$i]}\""
done
CONTEXTS_JSON+="]"

echo "Updating branch protection for $REPO (branch: $BRANCH) with required status checks: $CONTEXTS_JSON"

BODY=$(jq -n \
  --argjson contexts "$CONTEXTS_JSON" \
  '{
    required_status_checks: { strict: true, contexts: $contexts },
    enforce_admins: false,
    required_pull_request_reviews: { required_approving_review_count: 1, dismiss_stale_reviews: false },
    restrictions: null,
    allow_force_pushes: false,
    allow_deletions: false
  }')

echo "$BODY" | gh api "repos/$REPO/branches/$BRANCH/protection" \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --input -

echo "Done. Required status checks: $CONTEXTS_JSON"
