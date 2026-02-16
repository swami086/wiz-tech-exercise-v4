#!/usr/bin/env bash
# Create a Pull Request with intentional vulnerabilities for demo purposes.
#
# Use this to showcase the full PR process: status checks, Terraform validate,
# Trivy container scanning, and what happens when vulnerabilities are detected.
# The PR will have failing checks (container-scan due to CRITICAL/HIGH in base image).
# You can then fix by pushing a follow-up commit to the same branch and show checks turning green.
#
# Usage (from repo root):
#   ./Demo/create-demo-pr-vulnerabilities.sh
#   ./Demo/create-demo-pr-vulnerabilities.sh --also-terraform-fmt   # also break Terraform format so terraform-validate fails
#   ./Demo/create-demo-pr-vulnerabilities.sh --post-merge-demo     # after merging the PR: show Argo CD deploying the app into the cluster
#
# Requires: git, gh CLI (gh auth login), and a clean or committed working tree (except for --post-merge-demo).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BRANCH_NAME="${DEMO_PR_BRANCH:-demo/pr-vulnerability-scanning-showcase}"
ALSO_TERRAFORM_FMT=false
ALLOW_DIRTY=false
POST_MERGE_DEMO=false
for arg in "$@"; do
  if [[ "$arg" == "--also-terraform-fmt" ]]; then
    ALSO_TERRAFORM_FMT=true
  elif [[ "$arg" == "--allow-dirty" ]]; then
    ALLOW_DIRTY=true
  elif [[ "$arg" == "--post-merge-demo" ]]; then
    POST_MERGE_DEMO=true
  fi
done

# -----------------------------------------------------------------------------
# Post-merge: Show Argo CD deploying the app into the cluster
# -----------------------------------------------------------------------------
run_post_merge_argocd_demo() {
  echo "=== Post-merge: Argo CD deployment demo ==="
  echo "Shows how the app is deployed into the cluster by Argo CD after you merge the PR."
  echo ""

  # Resolve project and cluster from Terraform
  if [[ -z "${GCP_PROJECT_ID:-}" ]] && [[ -d "$REPO_ROOT/terraform" ]]; then
    GCP_PROJECT_ID=$(cd "$REPO_ROOT/terraform" && terraform output -raw project_id 2>/dev/null) || true
  fi
  [[ -n "${GCP_PROJECT_ID:-}" ]] || { echo "Error: set GCP_PROJECT_ID or run from a repo with terraform applied (project_id output)."; exit 1; }
  CLUSTER_NAME=$(cd "$REPO_ROOT/terraform" && terraform output -raw gke_cluster_name 2>/dev/null) || true
  GCP_REGION=$(cd "$REPO_ROOT/terraform" && terraform output -raw region 2>/dev/null) || true
  GCP_REGION="${GCP_REGION:-us-central1}"
  [[ -n "${CLUSTER_NAME:-}" ]] || { echo "Error: terraform output gke_cluster_name required."; exit 1; }

  command -v gcloud &>/dev/null || { echo "Error: gcloud required."; exit 1; }
  command -v kubectl &>/dev/null || { echo "Error: kubectl required."; exit 1; }

  echo "1. Getting GKE credentials (project=$GCP_PROJECT_ID, cluster=$CLUSTER_NAME)..."
  gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --quiet

  echo ""
  echo "2. Argo CD Application (GitOps source of truth for tasky)..."
  kubectl get application tasky -n argocd -o wide 2>/dev/null || { echo "   Application 'tasky' not found in namespace argocd. Is Argo CD installed and the Application created (argocd_enabled=true)?"; exit 1; }
  REV=$(kubectl get application tasky -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null) || true
  SYNC=$(kubectl get application tasky -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null) || true
  HEALTH=$(kubectl get application tasky -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null) || true
  echo "   Sync: $SYNC | Health: $HEALTH | Git revision: ${REV:-n/a}"
  echo "   (Argo CD syncs kubernetes/ from Git; image is overridden to Artifact Registry tasky:latest.)"

  echo ""
  echo "3. Rollout restart so deployment pulls the new image (pushed by Deploy workflow on merge)..."
  kubectl rollout restart deployment/tasky -n tasky
  kubectl rollout status deployment/tasky -n tasky --timeout=120s

  echo ""
  echo "4. Pods and Ingress (app deployed by Argo CD)..."
  kubectl get pods -n tasky -o wide
  kubectl get ingress -n tasky
  LB_IP=$(kubectl get ingress -n tasky -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -n "$LB_IP" ]]; then
    echo ""
    echo "5. App URL (via GCP Load Balancer): http://$LB_IP"
    curl -sf -o /dev/null -w "   HTTP check: %{http_code}\n" --connect-timeout 5 "http://$LB_IP" 2>/dev/null || true
  fi

  echo ""
  echo "6. Argo CD UI (optional): kubectl port-forward -n argocd svc/argocd-server 8080:443"
  echo "   Then open https://localhost:8080 (admin password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"
  echo ""
  echo "=== Argo CD deployment demo complete ==="
}

if [[ "$POST_MERGE_DEMO" == "true" ]]; then
  run_post_merge_argocd_demo
  exit 0
fi

# -----------------------------------------------------------------------------
# Ensure we're on main and up to date (or stash if --allow-dirty)
# -----------------------------------------------------------------------------
STASH_REF=""
if [[ -n $(git status -s) ]]; then
  if [[ "$ALLOW_DIRTY" == "true" ]]; then
    echo "Stashing local changes (--allow-dirty) so script can run..."
    git stash push -u -m "create-demo-pr-vulnerabilities: temporary stash"
    STASH_REF="1"
  else
    echo "Working tree has uncommitted changes. Commit or stash them, then run again."
    echo "Or use --allow-dirty to stash automatically and restore after."
    exit 1
  fi
fi

restore_stash() {
  if [[ -n "$STASH_REF" ]]; then
    echo "Restoring stashed changes..."
    git checkout main 2>/dev/null || true
    git stash pop
  fi
}
trap restore_stash EXIT

echo "Fetching latest main..."
git fetch origin main
git checkout main
git pull origin main

# -----------------------------------------------------------------------------
# Create branch and introduce intentional changes
# -----------------------------------------------------------------------------
echo "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# 1) Downgrade Dockerfile base image so Trivy finds CRITICAL/HIGH (OS + library)
#    Alpine 3.17.0 is old enough to have known CVEs; container-scan job will fail.
echo "Introducing intentional vulnerability: Alpine 3.19 -> 3.17.0 in Dockerfile..."
sed -i.bak 's|FROM alpine:3.19 AS release|FROM alpine:3.17.0 AS release|' "$REPO_ROOT/tasky-main/Dockerfile"
rm -f "$REPO_ROOT/tasky-main/Dockerfile.bak"

git add tasky-main/Dockerfile
git commit -m "demo: use older Alpine base (3.17.0) to trigger Trivy CRITICAL/HIGH in PR"

# 2) Optional: break Terraform format so terraform-validate fails
if [[ "$ALSO_TERRAFORM_FMT" == "true" ]]; then
  echo "Introducing Terraform format violation..."
  TF_FILE="$REPO_ROOT/terraform/variables.tf"
  # Add trailing spaces to a line (fmt -check will fail)
  if [[ -f "$TF_FILE" ]]; then
    sed -i.bak 's/^variable "project_id"/variable "project_id"   /' "$TF_FILE"
    rm -f "${TF_FILE}.bak"
    git add terraform/variables.tf
    git commit -m "demo: add trailing spaces to trigger terraform fmt -check failure in PR"
  fi
fi

# -----------------------------------------------------------------------------
# Push and open PR
# -----------------------------------------------------------------------------
echo "Pushing branch..."
git push -u origin "$BRANCH_NAME"

PR_BODY="## Demo PR: Vulnerability scanning and PR process

This PR is **for demonstration only**. It introduces an intentional change so you can showcase:

### What was changed
- **Dockerfile**: Release stage base image \`alpine:3.19\` → \`alpine:3.17.0\`.
- Alpine 3.17.0 has known CRITICAL/HIGH CVEs, so the **container-scan** job (Trivy) will **fail**.

### What to show in your demo
1. **Pull Request checks**  
   Go to the **Checks** tab (or the status checks at the bottom of this PR). You will see:
   - \`terraform-validate\` – should **pass** (no Terraform changes).
   - \`container-scan\` – will **fail** (Trivy found CRITICAL/HIGH).
   - \`deploy-gate\` – may pass or fail depending on workflow order.

2. **Failed job logs**  
   Click **Details** on the failed \`container-scan\` job. Show:
   - Docker build step.
   - Trivy scan step and the **table** of vulnerabilities (CRITICAL/HIGH).
   - Exit code 1 causing the job to fail.

3. **Security tab**  
   After the run, go to **Security** → **Code security** (or **Vulnerability alerts**).  
   Trivy SARIF is uploaded there (broader severity); you can show findings in the UI.

4. **Branch protection**  
   If \`main\` has required status checks (\`terraform-validate\`, \`container-scan\`, \`deploy-gate\`), this PR **cannot be merged** until checks pass – demonstrating that vulnerable images are blocked.

5. **Fix and re-run**  
   To show the full flow:
   - Push a commit that restores \`FROM alpine:3.19\` in \`tasky-main/Dockerfile\`.
   - Or merge a follow-up PR that fixes the base image.
   - Re-run the workflow and show all checks **passing** and merge enabled.

6. **After merge: Argo CD deployment**  
   Show how the app is deployed into the cluster by Argo CD: run \`./Demo/create-demo-pr-vulnerabilities.sh --post-merge-demo\` (gets GKE creds, shows Application status, rollout restart, pods, Ingress URL, and Argo CD UI command).

### How to fix (for demo)
Revert the Dockerfile change on this branch:
\`\`\`
# On branch $BRANCH_NAME
git checkout tasky-main/Dockerfile
# Edit: change alpine:3.17.0 back to alpine:3.19
git add tasky-main/Dockerfile
git commit -m \"fix: restore Alpine 3.19 to pass Trivy gate\"
git push origin $BRANCH_NAME
\`\`\`
Then watch the checks turn green on this PR.
"

if [[ "$ALSO_TERRAFORM_FMT" == "true" ]]; then
  PR_BODY="$PR_BODY

### Optional: Terraform format
This PR also includes a Terraform format violation so \`terraform-validate\` fails. Fix with \`terraform fmt -recursive\` in \`terraform/\` and commit.
"
fi

echo "Opening Pull Request..."
PR_URL=$(gh pr create \
  --base main \
  --head "$BRANCH_NAME" \
  --title "Demo: PR vulnerability scanning showcase (intentional Trivy failure)" \
  --body "$PR_BODY")

echo ""
echo "Done. Pull Request: $PR_URL"
echo ""
echo "Next steps:"
echo "  1. Open the PR and go to the Checks tab to show failing container-scan."
echo "  2. Click Details on container-scan to show Trivy vulnerability table."
echo "  3. Show Security tab for SARIF findings."
echo "  4. Fix the Dockerfile (alpine 3.17.0 -> 3.19), push to this branch, and show checks turning green."
echo "  5. Merge the PR once green."
echo "  6. After merge, show how the app is deployed by Argo CD:"
echo "     ./Demo/create-demo-pr-vulnerabilities.sh --post-merge-demo"
if [[ "$ALSO_TERRAFORM_FMT" == "true" ]]; then
  echo "  7. If terraform-validate failed: run 'terraform fmt -recursive' in terraform/ and push."
fi
