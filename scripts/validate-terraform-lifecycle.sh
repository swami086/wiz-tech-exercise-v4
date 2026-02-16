#!/usr/bin/env bash
# Validate Terraform lifecycle: plan (drift), validate (app/Mongo/misconfigs), or reproduce (destroy + apply).
# See docs/INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md.
#
# Usage (from repo root):
#   export GCP_PROJECT_ID="your-project-id"
#   ./scripts/validate-terraform-lifecycle.sh plan       # init + plan; exit 0 only if no changes
#   ./scripts/validate-terraform-lifecycle.sh validate  # post-apply: app HTTP, CRUD, Mongo, misconfigs; exit non-zero on any failure
#   REPRODUCE=1 ./scripts/validate-terraform-lifecycle.sh reproduce   # destroy then apply (destructive)
#
# Credentials: same as terraform-deploy.sh (key file in .keys/ or ADC).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
TASKY_NAMESPACE="${TASKY_NAMESPACE:-tasky}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

KEY_FILE="${REPO_ROOT}/.keys/wiz-exercise-automation-key.json"
if [[ -s "$KEY_FILE" ]]; then
  export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$KEY_FILE}"
  echo "Using key file: $GOOGLE_APPLICATION_CREDENTIALS"
else
  unset GOOGLE_APPLICATION_CREDENTIALS
  echo "Using Application Default Credentials (ADC)"
fi

BUCKET="${GCP_PROJECT_ID}-tfstate-wiz-exercise"

do_init() {
  echo "=== Terraform init (bucket: $BUCKET) ==="
  cd "$TERRAFORM_DIR"
  if [[ ! -f terraform.tfvars ]]; then
    echo "Error: terraform/terraform.tfvars not found. Copy from terraform.tfvars.example and set project_id and mongodb_admin_password/mongodb_app_password (min 32 chars). Tasky URI/secret can be left empty."
    exit 1
  fi
  terraform init \
    -backend-config="bucket=${BUCKET}" \
    -backend-config="prefix=terraform/state"
}

cmd_plan() {
  do_init
  echo "=== Terraform plan (lifecycle validation – expect no changes) ==="
  set +e
  terraform plan -detailed-exitcode -input=false -out=tfplan
  EXIT=$?
  set -e
  if [[ $EXIT -eq 0 ]]; then
    echo "Lifecycle validation passed: plan shows no changes (no drift)."
    exit 0
  fi
  if [[ $EXIT -eq 2 ]]; then
    echo "Lifecycle validation failed: plan has changes (drift or config change). Review above."
    exit 2
  fi
  echo "Terraform plan failed with exit code $EXIT."
  exit "$EXIT"
}

# Post-apply validation: app (HTTP 200 + CRUD), MongoDB ping, intentional misconfigs (bucket IAM, SSH firewall).
# Emits a summary table and exits non-zero on any failure. Uses plain variables for bash 3.x compatibility.
cmd_validate() {
  do_init
  cd "$TERRAFORM_DIR"
  CLUSTER_NAME=$(terraform output -raw gke_cluster_name 2>/dev/null || true)
  BACKUP_BUCKET=$(terraform output -raw mongodb_backup_bucket 2>/dev/null || true)
  MONGO_URI=$(terraform output -raw mongodb_connection_string 2>/dev/null || true)
  SSH_FW_NAME=$(terraform output -raw ssh_firewall_name 2>/dev/null || echo "wiz-exercise-allow-ssh-vm")

  echo "=== Post-apply validation (app, MongoDB, intentional misconfigs) ==="
  FAILED=0
  R_GKE="" R_INGRESS="" R_APP200="" R_CRUD="" R_MONGO="" R_BUCKET="" R_SSH=""

  # GKE credentials
  if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Error: could not get gke_cluster_name from Terraform output."
    exit 1
  fi
  if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null; then
    R_GKE="FAIL"
    ((FAILED++)) || true
    echo "  GKE credentials: FAIL (kubectl/gcloud cannot connect)"
  fi

  if [[ "$R_GKE" != "FAIL" ]]; then
    # Ingress IP
    INGRESS_IP=$(kubectl get ingress -n "$TASKY_NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -z "$INGRESS_IP" ]]; then
      R_INGRESS="FAIL"
      ((FAILED++)) || true
      echo "  Ingress IP: FAIL (no IP; is Tasky deployed and Ingress ready?)"
    else
      R_INGRESS="PASS"
      echo "  Ingress IP: $INGRESS_IP"

      # App: HTTP 200
      HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 15 "http://${INGRESS_IP}/" 2>/dev/null || echo "000")
      if [[ "$HTTP_CODE" == "200" ]]; then
        R_APP200="PASS"
        echo "  App HTTP 200: PASS"
      else
        R_APP200="FAIL (got $HTTP_CODE)"
        ((FAILED++)) || true
        echo "  App HTTP 200: FAIL (got $HTTP_CODE)"
      fi

      # CRUD path: GET /todos/1 (exercise read path; 2xx/4xx = app reached)
      CRUD_RAW=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://${INGRESS_IP}/todos/1" 2>/dev/null || echo "000")
      CRUD_CODE="${CRUD_RAW:0:3}"
      if [[ "$CRUD_CODE" == "200" || "$CRUD_CODE" == "404" || "$CRUD_CODE" == "401" || "$CRUD_CODE" =~ ^[24][0-9][0-9]$ ]]; then
        R_CRUD="PASS"
        echo "  App CRUD path (GET /todos/1): PASS (HTTP $CRUD_CODE)"
      else
        R_CRUD="FAIL (got $CRUD_RAW)"
        ((FAILED++)) || true
        echo "  App CRUD path: FAIL (got $CRUD_RAW)"
      fi
    fi

    # MongoDB ping (one-off pod with mongosh; URI from env only to avoid host-shell/special-char issues)
    if [[ -n "$MONGO_URI" ]]; then
      MONGO_NS="default"
      kubectl get namespace "$TASKY_NAMESPACE" &>/dev/null && MONGO_NS="$TASKY_NAMESPACE"
      MONGO_PING_OK=0
      MONGO_ERR=$(mktemp)
      for _attempt in 1 2; do
        if kubectl run mongo-ping-validate --rm -i --restart=Never -n "$MONGO_NS" \
          --image=mongo:6 \
          --env="MONGODB_URI=$MONGO_URI" \
          --timeout=90s \
          --command -- sh -c 'mongosh "$MONGODB_URI" --eval "db.adminCommand(\"ping\")"' 2>"$MONGO_ERR"; then
          MONGO_PING_OK=1
          break
        fi
        [[ $_attempt -eq 1 ]] && echo "  MongoDB ping: retry in 5s..." && sleep 5
      done
      if [[ $MONGO_PING_OK -eq 1 ]]; then
        R_MONGO="PASS"
        echo "  MongoDB ping: PASS"
      else
        R_MONGO="FAIL"
        ((FAILED++)) || true
        echo "  MongoDB ping: FAIL (one-off pod could not connect; check cluster→MongoDB VM network and URI)"
        [[ -s "$MONGO_ERR" ]] && echo "    Last error:" && head -20 "$MONGO_ERR"
      fi
      rm -f "$MONGO_ERR"
    else
      R_MONGO="SKIP (no output)"
      echo "  MongoDB ping: SKIP (mongodb_connection_string not available)"
    fi
  fi

  # Intentional misconfig: backup bucket has public read/list (allUsers)
  if [[ -n "$BACKUP_BUCKET" ]]; then
    if gsutil iam get "gs://${BACKUP_BUCKET}" 2>/dev/null | grep -q "allUsers"; then
      R_BUCKET="PASS (expected)"
      echo "  Misconfig bucket public IAM: PASS (allUsers present as expected)"
    else
      R_BUCKET="FAIL (allUsers not found)"
      ((FAILED++)) || true
      echo "  Misconfig bucket public IAM: FAIL (allUsers not found)"
    fi
  else
    R_BUCKET="SKIP"
    echo "  Misconfig bucket public IAM: SKIP (no bucket output)"
  fi

  # Intentional misconfig: SSH firewall allows 0.0.0.0/0
  SSH_FW_SOURCES=$(gcloud compute firewalls describe "$SSH_FW_NAME" --project="$GCP_PROJECT_ID" --format="value(sourceRanges)" 2>/dev/null || true)
  if [[ -n "$SSH_FW_SOURCES" ]] && echo "$SSH_FW_SOURCES" | tr ',' '\n' | grep -q "0.0.0.0/0"; then
    R_SSH="PASS (expected)"
    echo "  Misconfig SSH 0.0.0.0/0: PASS (expected)"
  else
    R_SSH="FAIL (rule missing or wrong source)"
    ((FAILED++)) || true
    echo "  Misconfig SSH 0.0.0.0/0: FAIL"
  fi

  echo ""
  echo "=== Summary ==="
  printf "%-35s %s\n" "Check" "Result"
  printf "%-35s %s\n" "-----" "------"
  printf "%-35s %s\n" "GKE credentials" "${R_GKE:---}"
  printf "%-35s %s\n" "Ingress IP" "${R_INGRESS:---}"
  printf "%-35s %s\n" "App HTTP 200" "${R_APP200:---}"
  printf "%-35s %s\n" "App CRUD path" "${R_CRUD:---}"
  printf "%-35s %s\n" "MongoDB ping" "${R_MONGO:---}"
  printf "%-35s %s\n" "Misconfig: bucket public IAM" "${R_BUCKET:---}"
  printf "%-35s %s\n" "Misconfig: SSH 0.0.0.0/0" "${R_SSH:---}"
  echo ""
  if [[ $FAILED -gt 0 ]]; then
    echo "Validation failed ($FAILED check(s) failed). Fix issues and re-run."
    exit 1
  fi
  echo "All validation checks passed."
  exit 0
}

cmd_reproduce() {
  if [[ "${REPRODUCE:-}" != "1" ]]; then
    echo "Reproduce mode is destructive (destroy then apply). Set REPRODUCE=1 to run."
    echo "  REPRODUCE=1 $0 reproduce"
    exit 1
  fi
  do_init
  echo "=== Reproduce: destroy then apply (project: $GCP_PROJECT_ID) ==="
  echo "This will destroy all Terraform-managed resources, then recreate them."
  read -r -p "Type 'yes' to continue: " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
  terraform destroy -auto-approve -input=false
  echo "=== Re-apply ==="
  terraform plan -out=tfplan -input=false
  terraform apply -input=false tfplan
  echo "Reproduce complete. Run './scripts/validate-terraform-lifecycle.sh validate' to run post-apply checks, then 'plan' to confirm no drift."
  exit 0
}

MODE="${1:-}"
case "$MODE" in
  plan)
    cmd_plan
    ;;
  validate)
    cmd_validate
    ;;
  reproduce)
    cmd_reproduce
    ;;
  *)
    echo "Usage: $0 plan | validate | reproduce"
    echo "  plan      – init + plan; exit 0 only if no changes (lifecycle validation)"
    echo "  validate  – post-apply: app HTTP/CRUD, MongoDB ping, misconfigs; summary table; exit non-zero on any failure"
    echo "  reproduce – destroy then apply (set REPRODUCE=1); destructive"
    exit 1
    ;;
esac
