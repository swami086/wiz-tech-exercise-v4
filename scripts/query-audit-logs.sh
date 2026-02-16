#!/usr/bin/env bash
# Query Cloud Audit Logs for security-relevant events (GCP Security Tooling ticket).
# Use for validation and to export sample logs for presentation.
#
# Prerequisites: gcloud CLI, authenticated with access to the project's logs.
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./scripts/query-audit-logs.sh [firewall|storage|compute-instances|all]

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
LIMIT="${AUDIT_LOG_LIMIT:-20}"
OUTPUT_DIR="${AUDIT_LOG_OUTPUT_DIR:-./audit-log-samples}"

if [[ -z "$GCP_PROJECT_ID" ]]; then
  echo "Error: GCP_PROJECT_ID is not set."
  echo "  export GCP_PROJECT_ID=your-project-id"
  exit 1
fi

query_firewall() {
  gcloud logging read '
    protoPayload.serviceName="compute.googleapis.com"
    (protoPayload.methodName="v1.compute.firewalls.insert" OR
     protoPayload.methodName="v1.compute.firewalls.patch" OR
     protoPayload.methodName="v1.compute.firewalls.delete")
  ' --project="$GCP_PROJECT_ID" --limit="$LIMIT" --format=json
}

query_storage() {
  gcloud logging read '
    protoPayload.serviceName="storage.googleapis.com"
  ' --project="$GCP_PROJECT_ID" --limit="$LIMIT" --format=json
}

query_compute_instances() {
  gcloud logging read '
    protoPayload.serviceName="compute.googleapis.com"
    protoPayload.methodName=~"v1.compute.instances.(insert|delete)"
  ' --project="$GCP_PROJECT_ID" --limit="$LIMIT" --format=json
}

run_query() {
  local name="$1"
  local query_fn="$2"
  echo "=== Audit log query: $name ==="
  if [[ -n "${OUTPUT_DIR}" ]]; then
    mkdir -p "$OUTPUT_DIR"
    local out="${OUTPUT_DIR}/${name}.json"
    "$query_fn" > "$out"
    echo "  Written to $out"
  else
    "$query_fn"
  fi
}

case "${1:-all}" in
  firewall)
    run_query "firewall" query_firewall
    ;;
  storage)
    run_query "storage" query_storage
    ;;
  compute-instances)
    run_query "compute-instances" query_compute_instances
    ;;
  all)
    run_query "firewall" query_firewall
    run_query "storage" query_storage
    run_query "compute-instances" query_compute_instances
    ;;
  *)
    echo "Usage: $0 [firewall|storage|compute-instances|all]"
    echo "  Optional: AUDIT_LOG_LIMIT=50 AUDIT_LOG_OUTPUT_DIR=./samples $0 all"
    exit 1
    ;;
esac
