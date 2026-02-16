# Cloud Audit Logs for Wiz Technical Exercise V4 (GCP Security Tooling ticket)
# Admin Activity is always on; we enable Data Access for Storage and Compute.
# System Event logs are included in the default logging bucket for the project.

# Data Access audit logs for Cloud Storage (bucket access, object read/write)
resource "google_project_iam_audit_config" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
  audit_log_config {
    log_type = "ADMIN_READ"
  }
}

# Data Access audit logs for Compute Engine (VM, firewall, disk operations)
resource "google_project_iam_audit_config" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
  audit_log_config {
    log_type = "ADMIN_READ"
  }
}
