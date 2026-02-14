# Variables for Wiz Technical Exercise V4 infrastructure (manual deployment phase)

variable "project_id" {
  description = "GCP project ID (e.g. CloudLabs project)"
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must be non-empty. Set a valid GCP project ID in terraform.tfvars or -var."
  }
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "us-central1"

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must be non-empty. Set a valid GCP region (e.g. us-central1) in terraform.tfvars or -var."
  }
}

variable "zone" {
  description = "GCP zone for zonal resources (VM, GKE node pool)"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = length(trimspace(var.zone)) > 0
    error_message = "zone must be non-empty. Set a valid GCP zone (e.g. us-central1-a) in terraform.tfvars or -var."
  }
}

variable "environment" {
  description = "Environment label (e.g. wiz-exercise)"
  type        = string
  default     = "wiz-exercise"
}

# --- Network ---

variable "vpc_cidr" {
  description = "CIDR for the main VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gke_subnet_cidr" {
  description = "CIDR for the GKE subnet (nodes)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vm_subnet_cidr" {
  description = "CIDR for the MongoDB VM subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# --- GKE ---

variable "gke_master_cidr" {
  description = "CIDR for GKE control plane (must not overlap with VPC)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_node_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}

# --- Naming (optional overrides) ---

variable "tf_state_bucket" {
  description = "GCS bucket name for Terraform state (used in backend; set when running init)"
  type        = string
  default     = ""
}

variable "backup_bucket_name" {
  description = "Name for MongoDB backup GCS bucket (globally unique). Leave empty to auto-generate from project_id"
  type        = string
  default     = ""
}

# --- MongoDB (startup script; required for automated VM setup) ---

variable "mongodb_admin_password" {
  description = "MongoDB admin user password. Generate with: openssl rand -base64 32"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mongodb_admin_password) >= 32
    error_message = "mongodb_admin_password must be at least 32 characters. Generate with: openssl rand -base64 32"
  }
}

variable "mongodb_app_password" {
  description = "MongoDB application user (todouser) password. Generate with: openssl rand -base64 32"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mongodb_app_password) >= 32
    error_message = "mongodb_app_password must be at least 32 characters. Generate with: openssl rand -base64 32"
  }
}

variable "mongodb_admin_user" {
  description = "MongoDB admin username (used by startup script)"
  type        = string
  default     = "admin"
}

variable "mongodb_app_user" {
  description = "MongoDB application username (used by startup script and Tasky)"
  type        = string
  default     = "todouser"
}

# --- Artifact Registry (Tasky image repository) ---

variable "artifact_registry_location" {
  description = "Artifact Registry repository location (e.g. region). Defaults to var.region."
  type        = string
  default     = ""
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID for Tasky images (default: tasky-repo)."
  type        = string
  default     = "tasky-repo"
}

variable "artifact_registry_format" {
  description = "Artifact Registry repository format (DOCKER)."
  type        = string
  default     = "DOCKER"
}

# --- Tasky app (Kubernetes deployment via Terraform) ---

variable "tasky_enabled" {
  description = "Deploy Tasky app to GKE via Terraform Kubernetes provider (namespace, deployment, service, ingress, RBAC). Default false; set true only after supplying tasky_mongodb_uri and tasky_secret_key."
  type        = bool
  default     = false
}

variable "tasky_image" {
  description = "Tasky container image. Defaults to REGION-docker.pkg.dev/PROJECT_ID/tasky-repo/tasky:latest when empty. Build and push with scripts/build-and-push-tasky.sh first."
  type        = string
  default     = ""
}

variable "tasky_mongodb_uri" {
  description = "MongoDB connection URI for Tasky (use mongodb_vm_internal_ip). Sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tasky_secret_key" {
  description = "JWT secret key for Tasky (at least 32 chars). Sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Argo CD GitOps (optional) ---

variable "argocd_enabled" {
  description = "Install Argo CD and deploy Tasky via GitOps (from kubernetes/ in Git). Set tasky_enabled=false when using this. Requires argocd_git_repo_url."
  type        = bool
  default     = false
}

variable "argocd_git_repo_url" {
  description = "Git repository URL for Argo CD to sync (e.g. https://github.com/your-org/Wiz). Required when argocd_enabled=true."
  type        = string
  default     = ""
}

variable "argocd_git_revision" {
  description = "Git branch or tag for Argo CD to sync"
  type        = string
  default     = "main"
}

# --- GCP Security Tooling (optional) ---

variable "enable_monitoring_alerts" {
  description = "Create Cloud Monitoring alert policies and optional notification channel (firewall/bucket IAM). Default false to avoid apply failures if the automation SA lacks roles/monitoring.alertPolicyEditor and roles/monitoring.notificationChannelEditor. Set to true after re-running scripts/gcp-bootstrap.sh (or manually granting those roles) so Terraform can create the alert resources."
  type        = bool
  default     = false
}

variable "alert_notification_email" {
  description = "Email for Cloud Monitoring alert notifications. Required when enable_monitoring_alerts is true. Set a valid email in terraform.tfvars so alert policies can notify."
  type        = string
  default     = ""
}

variable "enable_require_os_login" {
  description = "Enforce Organization Policy 'Require OS Login' at project level. Default false for lab projects that lack org-level orgpolicy.policyAdmin (e.g. CloudLabs); set the policy manually in Console or set this to true when org permissions exist."
  type        = bool
  default     = false
}
