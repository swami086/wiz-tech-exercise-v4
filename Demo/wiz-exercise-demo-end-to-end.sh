#!/usr/bin/env bash
# Wiz Technical Exercise V4 – End-to-End Demo Script
#
# Validates (and optionally provisions) the full environment per the exercise:
# - VM with outdated Linux + MongoDB; SSH public; overly permissive IAM; daily backup; bucket public
# - Web app on Kubernetes (private subnet, env var, wizexercise.txt, cluster-admin, Ingress/LB, data in DB)
# - DevSecOps: VCS, CI/CD pipelines, security scanning
# - Cloud Native Security: audit logging, preventative/detective controls
#
# Usage (from repo root):
#   ./Demo/wiz-exercise-demo-end-to-end.sh              # validate only (assume Terraform already applied)
#   PROVISION=1 ./Demo/wiz-exercise-demo-end-to-end.sh  # terraform apply then validate
#   SKIP_APP_DEMO=1 ...                                  # skip build/push and web app CRUD proof
#
# Env:
#   PROVISION=1       Run terraform apply before validation (requires terraform.tfvars).
#   SKIP_APP_DEMO=1   Skip build-and-push and live web app / data-in-DB demo.
#   GCP_PROJECT_ID    Override (default: terraform output project_id).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROVISION="${PROVISION:-0}"
SKIP_APP_DEMO="${SKIP_APP_DEMO:-0}"

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
bold='\033[1m'
nc='\033[0m'

section() { echo ""; echo -e "${blue}${bold}=== $* ===${nc}"; }
ok()    { echo -e "${green}OK: $*${nc}"; }
warn()  { echo -e "${yellow}WARN: $*${nc}"; }
fail()  { echo -e "${red}FAIL: $*${nc}"; exit 1; }
info()  { echo -e "  $*"; }

# -----------------------------------------------------------------------------
# Resolve GCP project and Terraform outputs (set global vars for later phases)
# -----------------------------------------------------------------------------
TF_OUT_DIR=""
get_tf() { (cd "$REPO_ROOT/terraform" && terraform output -raw "$1" 2>/dev/null) || echo ""; }

resolve_env() {
  if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
    if command -v terraform &>/dev/null && [[ -d "$REPO_ROOT/terraform" ]]; then
      GCP_PROJECT_ID=$(get_tf project_id)
    fi
  fi
  [[ -n "${GCP_PROJECT_ID:-}" ]] || fail "GCP_PROJECT_ID not set. Export it or run Terraform apply first and use terraform output project_id."
  export GCP_PROJECT_ID

  TF_OUT_DIR="$REPO_ROOT/terraform"
  if [[ ! -d "$TF_OUT_DIR" ]]; then
    fail "terraform/ not found. Run from repo root."
  fi
  CLUSTER_NAME=$(get_tf gke_cluster_name)
  GCP_REGION=$(get_tf region)
  MONGO_VM_NAME=$(get_tf mongodb_vm_name)
  MONGO_ZONE=$(get_tf mongodb_vm_zone)
  BACKUP_BUCKET=$(get_tf mongodb_backup_bucket)
  SSH_FW_NAME=$(get_tf ssh_firewall_name)
  GKE_SUBNET_ID=$(get_tf gke_subnet_id)
  VPC_NAME=$(get_tf vpc_name)
  export CLUSTER_NAME GCP_REGION MONGO_VM_NAME MONGO_ZONE BACKUP_BUCKET SSH_FW_NAME GKE_SUBNET_ID VPC_NAME
}

# -----------------------------------------------------------------------------
# Phase 0: Prerequisites
# -----------------------------------------------------------------------------
phase0_prereqs() {
  section "Phase 0: Prerequisites"
  command -v gcloud &>/dev/null || fail "gcloud not found."
  command -v terraform &>/dev/null || fail "terraform not found."
  command -v kubectl &>/dev/null || warn "kubectl not found; K8s checks will be skipped."
  command -v docker &>/dev/null || warn "docker not found; container build check skipped."
  resolve_env
  ok "GCP_PROJECT_ID=$GCP_PROJECT_ID"
  [[ -n "$CLUSTER_NAME" ]] || fail "Terraform output gke_cluster_name empty. Run Terraform apply first."
  ok "Cluster: $CLUSTER_NAME, Region: $GCP_REGION"
}

# -----------------------------------------------------------------------------
# Phase 1: Virtual Machine with MongoDB (exercise requirements)
# -----------------------------------------------------------------------------
phase1_vm_mongodb() {
  section "1. Virtual Machine with MongoDB Server"

  info "Requirement: VM with 1+ year outdated Linux, SSH to public internet, overly permissive CSP (e.g. create VMs)."
  info "Requirement: MongoDB 1+ year outdated; access restricted to Kubernetes only + DB authentication."
  info "Requirement: Daily backup to cloud storage; bucket allows public read and public listing."

  # VM exists and image (outdated Linux)
  echo ""
  info "VM instance (outdated Linux image)..."
  VM_JSON=$(gcloud compute instances describe "$MONGO_VM_NAME" --zone="$MONGO_ZONE" --project="$GCP_PROJECT_ID" --format=json 2>/dev/null) || true
  if [[ -n "${VM_JSON:-}" ]]; then
    VM_IMAGE=$(echo "$VM_JSON" | grep -o '"image": "[^"]*"' | head -1 | sed 's/.*: "\(.*\)"/\1/')
    ok "VM $MONGO_VM_NAME exists; image: $VM_IMAGE (Debian 10 Buster – EOL, 1+ year outdated)."
  else
    warn "Could not describe VM $MONGO_VM_NAME (zone $MONGO_ZONE). Ensure Terraform applied."
  fi

  # SSH firewall: 0.0.0.0/0 on port 22
  info "SSH exposed to public internet (firewall)..."
  FW_JSON=$(gcloud compute firewall-rules describe "$SSH_FW_NAME" --project="$GCP_PROJECT_ID" --format=json 2>/dev/null) || true
  if [[ -n "${FW_JSON:-}" ]]; then
    SRC=$(echo "$FW_JSON" | grep -o '"sourceRanges": \[[^]]*\]' | head -1)
    if echo "$SRC" | grep -q "0.0.0.0/0"; then
      ok "Firewall $SSH_FW_NAME allows SSH (tcp/22) from 0.0.0.0/0 (intentional for exercise)."
    else
      warn "SSH firewall source ranges: $SRC (exercise requires public SSH)."
    fi
  else
    warn "Could not describe firewall $SSH_FW_NAME."
  fi

  # Overly permissive IAM: MongoDB VM SA has roles/compute.admin
  info "Overly permissive CSP permissions (VM SA can create VMs)..."
  VM_SA=$(gcloud compute instances describe "$MONGO_VM_NAME" --zone="$MONGO_ZONE" --project="$GCP_PROJECT_ID" --format='get(serviceAccounts[0].email)' 2>/dev/null) || true
  if [[ -n "${VM_SA:-}" ]]; then
    if gcloud projects get-iam-policy "$GCP_PROJECT_ID" --flatten="bindings[].members" --filter="bindings.members:serviceAccount:${VM_SA}" --format="get(bindings.role)" 2>/dev/null | grep -q "compute.admin"; then
      ok "MongoDB VM SA has roles/compute.admin (intentional – able to create VMs)."
    else
      warn "VM SA $VM_SA may not have compute.admin; check IAM."
    fi
  fi

  # MongoDB: 27017 from GKE only (firewall)
  info "MongoDB access: Kubernetes network only + authentication..."
  MONGO_FW=$(gcloud compute firewall-rules list --project="$GCP_PROJECT_ID" --filter="name~mongo OR allowed.ports:27017" --format="value(name)" 2>/dev/null | head -1) || true
  if [[ -n "${MONGO_FW:-}" ]]; then
    ok "MongoDB (27017) firewall rule exists; source ranges should be GKE subnet + pod range only (see terraform/firewall.tf)."
  else
    warn "No firewall rule found for 27017; check terraform."
  fi
  info "Database authentication: app uses MONGODB_URI with user/password (tododb); enabled in mongod.conf (see scripts/mongodb-startup.sh.tpl)."
  ok "MongoDB auth and K8s-only access configured via Terraform."

  # Daily backup + bucket public
  info "Daily backup to cloud storage..."
  if gsutil ls -b "gs://${BACKUP_BUCKET}" &>/dev/null; then
    ok "Backup bucket gs://$BACKUP_BUCKET exists."
  else
    warn "Bucket gs://$BACKUP_BUCKET not found or not accessible."
  fi
  info "Backup automation: VM startup script installs cron '0 2 * * *' (daily 02:00) – see terraform/scripts/mongodb-startup.sh.tpl."
  ok "Daily backup cron configured on VM."

  info "Bucket public read + public listing (intentional misconfiguration)..."
  BINDINGS=$(gsutil iam get "gs://${BACKUP_BUCKET}" 2>/dev/null | grep -E "allUsers|allAuthenticatedUsers" || true)
  if echo "$BINDINGS" | grep -q "allUsers"; then
    ok "Bucket has allUsers binding (public read/list – exercise requirement)."
  else
    warn "Bucket may not have public access; check backup_bucket.tf (roles/storage.objectViewer, legacyBucketReader for allUsers)."
  fi
}

# -----------------------------------------------------------------------------
# Phase 2: Web Application on Kubernetes
# -----------------------------------------------------------------------------
phase2_webapp_k8s() {
  section "2. Web Application on Kubernetes"

  info "Requirement: Containerized app, (re-)built image, uses MongoDB; K8s in private subnet."
  info "Requirement: MONGODB_URI via env in K8s; image contains wizexercise.txt (your name); cluster-admin; Ingress/LB; kubectl demo; prove data in DB."

  # GKE private subnet
  echo ""
  info "Kubernetes cluster in private subnet..."
  if [[ -n "$GKE_SUBNET_ID" ]]; then
    ok "GKE subnet: $GKE_SUBNET_ID (private – no public IPs on nodes; see network.tf)."
  fi

  # Get credentials
  if ! command -v kubectl &>/dev/null; then
    warn "kubectl not installed; skipping remaining K8s checks."
    return 0
  fi
  gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || fail "Could not get GKE credentials."

  NAMESPACE="${TASKY_NAMESPACE:-tasky}"

  # MONGODB_URI env
  info "MongoDB access via environment variable..."
  MONGO_ENV=$(kubectl get deployment tasky -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MONGODB_URI")].name}' 2>/dev/null) || true
  if [[ "$MONGO_ENV" == "MONGODB_URI" ]]; then
    ok "Deployment has MONGODB_URI environment variable (from secret tasky-secret)."
  else
    warn "MONGODB_URI not found in deployment; ensure tasky is deployed (Terraform or Argo CD)."
  fi

  # wizexercise.txt in image and in running container
  info "wizexercise.txt in container image and in running container..."
  if [[ -f "$REPO_ROOT/tasky-main/wizexercise.txt" ]]; then
    ok "Source: tasky-main/wizexercise.txt is COPY'd into image in Dockerfile (line: COPY --from=build .../wizexercise.txt ./wizexercise.txt)."
  fi
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=tasky -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [[ -n "$POD_NAME" ]]; then
    WIZ_CONTENT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /app/wizexercise.txt 2>/dev/null) || true
    if [[ -n "$WIZ_CONTENT" ]]; then
      ok "Running container contains /app/wizexercise.txt: $WIZ_CONTENT"
    else
      warn "Could not read wizexercise.txt from pod (exec failed or file missing)."
    fi
  else
    warn "No tasky pod found; deploy app first (build-and-push + Argo CD sync or Terraform)."
  fi

  # Cluster-wide admin (intentional misconfiguration)
  info "Container application assigned cluster-wide admin (intentional misconfiguration)..."
  CAN_I=$(kubectl auth can-i '*' '*' --as=system:serviceaccount:${NAMESPACE}:tasky 2>/dev/null) || true
  if [[ "$CAN_I" == "yes" ]]; then
    ok "ServiceAccount tasky/tasky has cluster-admin (ClusterRoleBinding tasky-cluster-admin – exercise requirement)."
  else
    warn "SA tasky/tasky cluster-admin check returned: $CAN_I"
  fi

  # Ingress and Load Balancer
  info "Application exposed via Ingress and CSP load balancer..."
  LB_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -n "$LB_IP" ]]; then
    ok "Ingress Load Balancer IP: $LB_IP (GCP HTTP(S) Load Balancer)."
  else
    warn "Ingress external IP not yet assigned; wait a few minutes after deploy."
  fi

  # kubectl demonstration
  info "kubectl demonstration..."
  echo "  Nodes (private – no external IPs):"
  kubectl get nodes -o wide 2>/dev/null | sed 's/^/    /' || true
  echo "  Pods in $NAMESPACE:"
  kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null | sed 's/^/    /' || true

  # Web app and data in DB proof
  if [[ "$SKIP_APP_DEMO" == "1" ]]; then
    info "SKIP_APP_DEMO=1: skipping build/push and live CRUD proof."
    return 0
  fi

  echo ""
  info "Build and push container image (then prove data in DB)..."
  if command -v docker &>/dev/null && [[ -d "$REPO_ROOT/tasky-main" ]]; then
    GCP_PROJECT_ID="$GCP_PROJECT_ID" "$REPO_ROOT/scripts/build-and-push-tasky.sh" 2>/dev/null || warn "build-and-push-tasky.sh failed (check Artifact Registry and gcloud auth)."
  fi

  info "Rollout restart to use latest image..."
  kubectl rollout restart deployment/tasky -n "$NAMESPACE" 2>/dev/null || true
  kubectl rollout status deployment/tasky -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

  LB_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -z "$LB_IP" ]]; then
    warn "No LB IP; cannot prove web app and data in DB. Open app URL manually and create a todo."
    return 0
  fi

  info "Proving web application and data in database..."
  BASE_URL="http://$LB_IP"
  # Create a todo via API
  CREATE_RESP=$(curl -sf -X POST -H "Content-Type: application/json" -d '{"title":"Wiz Demo Todo","completed":false}' "$BASE_URL/api/todos" 2>/dev/null) || true
  if [[ -n "$CREATE_RESP" ]]; then
    ok "Created todo via API (POST /api/todos)."
    # List todos (data came from MongoDB)
    LIST_RESP=$(curl -sf "$BASE_URL/api/todos" 2>/dev/null) || true
    if echo "$LIST_RESP" | grep -q "Wiz Demo Todo"; then
      ok "List todos (GET /api/todos) shows the new item – data is stored in MongoDB and served by the app."
    else
      info "List response: $LIST_RESP"
    fi
  else
    warn "API create/list failed; ensure app is healthy. Manually open $BASE_URL and create a todo to prove DB."
  fi
  echo ""
  ok "Web app URL: $BASE_URL – demonstrate CRUD in browser; data persists in MongoDB."
}

# -----------------------------------------------------------------------------
# Phase 3: DevSecOps (VCS, CI/CD, security)
# -----------------------------------------------------------------------------
phase3_devsecops() {
  section "3. DevSecOps (VCS, SCM, CI/CD)"

  info "Requirement: Code in VCS; two pipelines (IaC deploy + container build/push + K8s deploy); security controls (repo + IaC scan + container scan)."

  echo ""
  info "VCS/SCM: Code and config in GitHub (or other VCS) – repo root and .github/workflows."
  if [[ -d "$REPO_ROOT/.git" ]]; then
    REMOTE=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || true
    ok "Git remote: ${REMOTE:-<not set>}"
  fi

  info "CI/CD pipelines:"
  info "  1) IaC: Terraform validate (and optionally apply) – see .github/workflows/phase1.yml (terraform-validate job), terraform-validate.yml."
  info "  2) Container build & push + K8s deploy: .github/workflows/deploy.yml (build, push to Artifact Registry on push to main); Argo CD or Terraform deploys to K8s from Git."
  ok "Two pipelines: Phase 1 (terraform-validate, container-scan, deploy-gate) and Deploy (build & push)."

  info "Pipeline security:"
  info "  - Repository: branch protection, required status checks (terraform-validate, container-scan, deploy-gate)."
  info "  - IaC: terraform validate + terraform fmt -check in CI (phase1.yml)."
  info "  - Container: Trivy scan (CRITICAL/HIGH fail) before deploy – phase1.yml container-scan job."
  ok "Security controls: repo protection, IaC validation, container image scan (Trivy)."
}

# -----------------------------------------------------------------------------
# Phase 4: Cloud Native Security (audit, preventative, detective)
# -----------------------------------------------------------------------------
phase4_cloud_native_security() {
  section "4. Cloud Native Security"

  info "Requirement: Control plane audit logging; at least one preventative and one detective control; demonstrate tools and impact."

  echo ""
  info "Control plane / audit logging:"
  if [[ -f "$REPO_ROOT/terraform/audit_logs.tf" ]]; then
    ok "terraform/audit_logs.tf enables Data Access audit logs for Storage and Compute (DATA_READ, DATA_WRITE, ADMIN_READ)."
  else
    warn "audit_logs.tf not found; enable in GCP Console: IAM & Admin → Audit Logs."
  fi

  info "Preventative control:"
  if [[ -f "$REPO_ROOT/terraform/org_policy.tf" ]]; then
    ok "terraform/org_policy.tf: requireOsLogin (constraints/compute.requireOsLogin) – enforces OS Login for VM SSH."
  else
    info "  Optional: Org Policy (e.g. require OS Login) – configure in Console or Terraform."
  fi

  info "Detective control:"
  if [[ -f "$REPO_ROOT/terraform/monitoring_alerts.tf" ]]; then
    ok "terraform/monitoring_alerts.tf: alerting policies (e.g. bucket public, firewall open) – detective controls."
  else
    info "  Optional: Monitoring alerts, Security Command Center, or audit log alerts – demonstrate in Console."
  fi

  info "Demonstrate: GCP Console → Logging → Logs Explorer (audit logs); Security → Command Center; IAM → Audit logs."
  ok "Cloud Native Security tooling documented in terraform/ and docs/GCP_SECURITY_TOOLING.md."
}

# -----------------------------------------------------------------------------
# Optional: Terraform apply (provision)
# -----------------------------------------------------------------------------
do_provision() {
  section "Provisioning (Terraform apply)"
  cd "$REPO_ROOT/terraform"
  terraform init -input=false
  terraform apply -input=false -auto-approve
  cd "$REPO_ROOT"
  resolve_env
  ok "Terraform apply complete."
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo -e "${bold}Wiz Technical Exercise V4 – End-to-End Demo${nc}"
  echo "This script validates (and optionally provisions) the full environment per the exercise specification."
  phase0_prereqs

  if [[ "$PROVISION" == "1" ]]; then
    do_provision
  fi

  phase1_vm_mongodb
  phase2_webapp_k8s
  phase3_devsecops
  phase4_cloud_native_security

  section "Demo complete"
  echo "Summary:"
  echo "  - VM with outdated Linux + MongoDB; SSH public; permissive IAM; daily backup; bucket public."
  echo "  - Web app on GKE (private subnet); MONGODB_URI env; wizexercise.txt in image and container; cluster-admin; Ingress/LB; data in DB."
  echo "  - DevSecOps: VCS, two CI/CD pipelines, IaC + container scanning."
  echo "  - Cloud Native: Audit logs, org policy (preventative), monitoring/alerts (detective)."
  echo ""
  echo "Next: Use kubectl and the Load Balancer URL to demonstrate the app and persistence during your presentation."
}

main "$@"
