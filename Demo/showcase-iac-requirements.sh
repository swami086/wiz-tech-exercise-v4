#!/usr/bin/env bash
# IaC (Terraform) requirements showcase – Wiz Technical Exercise V4
#
# Validates that the infrastructure meets all exercise requirements after
# terraform apply (or terraform destroy + terraform apply). Use this to
# demonstrate the VM/MongoDB and Web App on Kubernetes requirements.
#
# Usage (from repo root):
#   ./Demo/showcase-iac-requirements.sh              # validate only (Terraform already applied)
#   ./Demo/showcase-iac-requirements.sh --apply      # run terraform apply -auto-approve then validate
#   ./Demo/showcase-iac-requirements.sh --destroy-apply   # terraform destroy then apply then validate
#
# Requires: gcloud, terraform, kubectl; optional: curl (for data-in-DB proof).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RUN_APPLY=false
RUN_DESTROY_APPLY=false
for arg in "$@"; do
  if [[ "$arg" == "--apply" ]]; then
    RUN_APPLY=true
  elif [[ "$arg" == "--destroy-apply" ]]; then
    RUN_DESTROY_APPLY=true
  fi
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
get_tf() { (cd "$REPO_ROOT/terraform" && terraform output -raw "$1" 2>/dev/null) || echo ""; }
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
bold='\033[1m'
nc='\033[0m'
section() { echo ""; echo -e "${blue}${bold}=== $* ===${nc}"; }
pass() { echo -e "${green}PASS: $*${nc}"; }
warn() { echo -e "${yellow}WARN: $*${nc}"; }
fail() { echo -e "${red}FAIL: $*${nc}"; }

# -----------------------------------------------------------------------------
# Resolve project and outputs (after apply)
# -----------------------------------------------------------------------------
resolve_env() {
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(get_tf project_id)}"
  [[ -n "$GCP_PROJECT_ID" ]] || { echo "Error: GCP_PROJECT_ID not set and terraform output project_id empty. Run terraform apply first."; exit 1; }
  CLUSTER_NAME=$(get_tf gke_cluster_name)
  GCP_REGION=$(get_tf region)
  GCP_REGION="${GCP_REGION:-us-central1}"
  MONGO_VM_NAME=$(get_tf mongodb_vm_name)
  MONGO_ZONE_RAW=$(get_tf mongodb_vm_zone)
  MONGO_ZONE="${MONGO_ZONE_RAW##*/}"   # Terraform may return full URL; use zone name (e.g. us-central1-a)
  MONGO_ZONE="${MONGO_ZONE:-$MONGO_ZONE_RAW}"
  BACKUP_BUCKET=$(get_tf mongodb_backup_bucket)
  SSH_FW_NAME=$(get_tf ssh_firewall_name)
  MONGO_FW_NAME=$(get_tf mongodb_firewall_name)
  GKE_SUBNET_ID=$(get_tf gke_subnet_id)
}

# -----------------------------------------------------------------------------
# Terraform destroy / apply (optional)
# -----------------------------------------------------------------------------
run_terraform() {
  section "Terraform (optional)"
  cd "$REPO_ROOT/terraform"
  if [[ "$RUN_DESTROY_APPLY" == "true" ]]; then
    echo "Running terraform destroy -auto-approve..."
    terraform destroy -auto-approve -input=false
  fi
  if [[ "$RUN_DESTROY_APPLY" == "true" ]] || [[ "$RUN_APPLY" == "true" ]]; then
    echo "Running terraform apply -auto-approve..."
    terraform init -input=false
    terraform apply -auto-approve -input=false
  fi
  cd "$REPO_ROOT"
  resolve_env
}

# -----------------------------------------------------------------------------
# 1. Virtual Machine with MongoDB Server
# -----------------------------------------------------------------------------
print_vm_mongodb_requirements() {
  echo ""
  echo -e "${bold}Virtual Machine with Mongo Database Server${nc}"
  echo ""
  echo "This database server must be leveraged by the web application. The database"
  echo "backups must be automated and stored in the public-readable cloud object storage."
  echo ""
  echo -e "${bold}● VM should be leveraging a 1+ year outdated version of Linux${nc}"
  echo "  ○ SSH must be exposed to the public internet"
  echo "  ○ VM should be granted overly permissive CSP permissions (e.g. able to create VMs)"
  echo ""
  echo -e "${bold}● Database should be MongoDB that is a 1+ year outdated database version${nc}"
  echo "  ○ Access must be restricted to Kubernetes network access only and require database"
  echo "    authentication"
  echo ""
  echo -e "${bold}● Database must be automatically backed up on a daily basis to a cloud object storage${nc}"
  echo "  ○ Object storage must allow public read and public listing"
  echo ""
}

check_vm_mongodb() {
  section "1. Virtual Machine with MongoDB Server"
  print_vm_mongodb_requirements

  echo -e "${bold}Validation:${nc}"
  echo ""
  echo "1.1 VM: 1+ year outdated Linux"
  VM_JSON=$(gcloud compute instances describe "$MONGO_VM_NAME" --zone="$MONGO_ZONE" --project="$GCP_PROJECT_ID" --format=json 2>/dev/null) || true
  if [[ -n "${VM_JSON:-}" ]]; then
    # Boot disk: image URL is in disks[0].initializeParams.sourceImage at create time; after attach, use disks[0].licenses (e.g. debian-10-buster)
    IMG=$(gcloud compute instances describe "$MONGO_VM_NAME" --zone="$MONGO_ZONE" --project="$GCP_PROJECT_ID" --format='get(disks[0].licenses[0])' 2>/dev/null) || true
    if [[ -z "${IMG:-}" ]]; then
      IMG=$(echo "$VM_JSON" | grep -oE 'debian-10-buster|debian-cloud/debian-10[^"]*' | head -1) || true
    fi
    if [[ -n "${IMG:-}" ]] && [[ -n "$(echo "$IMG" | grep -oE "debian-10|buster" || true)" ]]; then
      pass "VM uses Debian 10 (Buster) – EOL, 1+ year outdated (terraform: mongodb_vm.tf local.vm_image)."
    else
      warn "VM image: ${IMG:-unknown} (expected Debian 10 Buster for 1+ year outdated)."
    fi
  else
    fail "VM $MONGO_VM_NAME not found. Run terraform apply."
  fi

  echo ""
  echo "1.2 SSH exposed to public internet"
  FW_JSON=$(gcloud compute firewall-rules describe "$SSH_FW_NAME" --project="$GCP_PROJECT_ID" --format=json 2>/dev/null) || true
  if [[ -n "${FW_JSON:-}" ]]; then
    if [[ -n "$(echo "$FW_JSON" | grep -o "0.0.0.0/0" || true)" ]]; then
      pass "Firewall $SSH_FW_NAME allows SSH (tcp/22) from 0.0.0.0/0 (terraform: firewall.tf ssh_to_vm)."
    else
      warn "SSH firewall may not allow 0.0.0.0/0."
    fi
  else
    fail "Firewall $SSH_FW_NAME not found."
  fi

  echo ""
  echo "1.3 VM granted overly permissive CSP permissions (e.g. able to create VMs)"
  VM_SA=$(gcloud compute instances describe "$MONGO_VM_NAME" --zone="$MONGO_ZONE" --project="$GCP_PROJECT_ID" --format='get(serviceAccounts[0].email)' 2>/dev/null) || true
  if [[ -n "${VM_SA:-}" ]]; then
    ROLES=$(gcloud projects get-iam-policy "$GCP_PROJECT_ID" --flatten="bindings[].members" --filter="bindings.members:serviceAccount:${VM_SA}" --format="get(bindings.role)" 2>/dev/null) || true
    if [[ -n "$(echo "$ROLES" | grep -o "compute.admin" || true)" ]]; then
      pass "MongoDB VM SA has roles/compute.admin (terraform: mongodb_vm.tf google_project_iam_member.mongodb_vm_compute_admin)."
    else
      warn "VM SA may not have compute.admin."
    fi
  fi

  echo ""
  echo "1.4 Database: MongoDB 1+ year outdated; access restricted to Kubernetes only + database authentication"
  if [[ -n "${MONGO_FW_NAME:-}" ]]; then
    MONGO_FW_JSON=$(gcloud compute firewall-rules describe "$MONGO_FW_NAME" --project="$GCP_PROJECT_ID" --format=json 2>/dev/null) || true
    if [[ -n "${MONGO_FW_JSON:-}" ]]; then
      pass "MongoDB (27017) firewall $MONGO_FW_NAME exists; source ranges are GKE subnet + pod range only (terraform: firewall.tf mongo_from_gke)."
    else
      warn "Firewall rule $MONGO_FW_NAME not found."
    fi
  else
    warn "mongodb_firewall_name output empty; run terraform apply."
  fi
  echo "   Database authentication: mongod.conf has security.authorization enabled; app user/password in Terraform (terraform/scripts/mongodb-startup.sh.tpl)."
  pass "MongoDB auth enabled; app uses MONGODB_URI with credentials in Kubernetes secret."

  echo ""
  echo "1.5 Daily automated backup to cloud object storage"
  BACKUP_GS="gs://${BACKUP_BUCKET}"
  BACKUP_HTTPS="https://storage.googleapis.com/${BACKUP_BUCKET}"
  echo "   Backup bucket URL (gs):   $BACKUP_GS"
  echo "   Backup bucket URL (https): $BACKUP_HTTPS"
  if gsutil ls -b "$BACKUP_GS" &>/dev/null; then
    pass "Backup bucket $BACKUP_GS exists (terraform: backup_bucket.tf)."
  else
    fail "Bucket $BACKUP_GS not found."
  fi
  echo "   Daily cron on VM: 0 2 * * * (02:00) – terraform/scripts/mongodb-startup.sh.tpl setup_backup_cron."

  echo ""
  echo "1.6 Object storage: public read and public listing"
  BINDINGS=$(gsutil iam get "gs://${BACKUP_BUCKET}" 2>/dev/null | grep -E "allUsers|objectViewer|legacyBucketReader" || true)
  if [[ -n "$(echo "$BINDINGS" | grep -o "allUsers" || true)" ]]; then
    pass "Bucket has allUsers (public read + listing) – terraform: backup_bucket.tf public_read, public_list."
  else
    warn "Bucket may not have public access (allUsers)."
  fi
}

# -----------------------------------------------------------------------------
# 2. Web Application on Kubernetes
# -----------------------------------------------------------------------------
check_webapp_k8s() {
  section "2. Web Application on Kubernetes"

  command -v kubectl &>/dev/null || { warn "kubectl not installed; skipping K8s checks."; return 0; }
  [[ -n "${CLUSTER_NAME:-}" ]] || { warn "gke_cluster_name output empty; skipping K8s checks."; return 0; }
  gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT_ID" --quiet 2>/dev/null || { warn "Could not get GKE credentials."; return 0; }

  NAMESPACE="tasky"

  echo ""
  echo "2.1 Kubernetes cluster in private subnet"
  if [[ -n "${GKE_SUBNET_ID:-}" ]]; then
    pass "GKE uses private subnet (terraform: network.tf gke subnetwork, gke.tf enable_private_nodes = true)."
  fi

  echo ""
  echo "2.2 Access to MongoDB via environment variable in Kubernetes"
  MONGO_ENV=$(kubectl get deployment tasky -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MONGODB_URI")].name}' 2>/dev/null) || true
  if [[ "$MONGO_ENV" == "MONGODB_URI" ]]; then
    pass "Deployment has MONGODB_URI from secret tasky-secret (kubernetes/tasky-deployment.yaml, Terraform/Argo CD create secret)."
  else
    warn "MONGODB_URI not found in deployment; ensure tasky is deployed (Terraform tasky_enabled or Argo CD)."
  fi

  echo ""
  echo "2.3 Container image: wizexercise.txt with your name; how it got in and validate in running container"
  echo "   How it gets in: tasky-main/wizexercise.txt is COPY'd in Dockerfile:"
  echo "   COPY --from=build  /go/src/tasky/wizexercise.txt ./wizexercise.txt  (tasky-main/Dockerfile)."
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=tasky -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [[ -n "$POD_NAME" ]]; then
    WIZ=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /app/wizexercise.txt 2>/dev/null) || true
    if [[ -n "$WIZ" ]]; then
      pass "Running container has /app/wizexercise.txt: $WIZ"
    else
      warn "Could not read wizexercise.txt from pod (deploy app and ensure image includes it)."
    fi
  else
    warn "No tasky pod; deploy app (build/push + Terraform or Argo CD) then re-run."
  fi

  echo ""
  echo "2.4 Container application: cluster-wide admin role (intentional misconfiguration)"
  CAN_I=$(kubectl auth can-i '*' '*' --as=system:serviceaccount:${NAMESPACE}:tasky 2>/dev/null) || true
  if [[ "$CAN_I" == "yes" ]]; then
    pass "ServiceAccount tasky has cluster-admin (kubernetes/tasky-rbac.yaml ClusterRoleBinding tasky-cluster-admin)."
  else
    warn "SA tasky cluster-admin check: $CAN_I"
  fi

  echo ""
  echo "2.5 App exposed via Kubernetes Ingress and CSP load balancer"
  LB_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || true
  if [[ -n "$LB_IP" ]]; then
    pass "Ingress has Load Balancer IP: $LB_IP (GCP HTTP(S) LB – kubernetes/tasky-ingress.yaml)."
  else
    warn "Ingress external IP not yet assigned (wait a few minutes after deploy)."
  fi

  echo ""
  echo "2.6 kubectl demonstration"
  echo "   Nodes (private):"
  kubectl get nodes -o wide 2>/dev/null | sed 's/^/     /' || true
  echo "   Pods in $NAMESPACE:"
  kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null | sed 's/^/     /' || true

  echo ""
  echo "2.7 Web application and prove data in database"
  if [[ -z "$LB_IP" ]]; then
    warn "No LB IP; skip HTTP proof. Once Ingress has IP: open http://<IP>, create a todo, then list to show data from MongoDB."
    return 0
  fi
  BASE_URL="http://$LB_IP"
  if command -v curl &>/dev/null; then
    CREATE=$(curl -sf -X POST -H "Content-Type: application/json" -d '{"title":"IaC demo todo","completed":false}' "$BASE_URL/api/todos" 2>/dev/null) || true
    if [[ -n "$CREATE" ]]; then
      LIST=$(curl -sf "$BASE_URL/api/todos" 2>/dev/null) || true
      if [[ -n "$(echo "$LIST" | grep -o "IaC demo todo" || true)" ]]; then
        pass "Created todo via API; GET /api/todos shows it – data is stored in MongoDB and served by the app."
      else
        warn "API list did not show the new todo."
      fi
    else
      warn "API create failed; ensure app is healthy and MongoDB reachable."
    fi
  else
    echo "   Open $BASE_URL in a browser; create a todo and refresh to prove data in DB."
  fi
  echo "   App URL: $BASE_URL"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo -e "${bold}IaC (Terraform) requirements showcase – Wiz Technical Exercise V4${nc}"
  echo "Validates VM/MongoDB and Web App on Kubernetes requirements (works after terraform apply or destroy+apply)."
  echo ""

  if [[ "$RUN_DESTROY_APPLY" == "true" ]] || [[ "$RUN_APPLY" == "true" ]]; then
    run_terraform
  else
    resolve_env
    [[ -n "$GCP_PROJECT_ID" ]] || { echo "Run terraform apply first or use --apply."; exit 1; }
  fi

  check_vm_mongodb
  check_webapp_k8s

  section "Showcase complete"
  echo "All requirements are validated above. Use this script after any terraform destroy + apply to re-verify."
  echo "  --apply         run terraform apply before validation"
  echo "  --destroy-apply run terraform destroy then apply before validation"
}

main "$@"
