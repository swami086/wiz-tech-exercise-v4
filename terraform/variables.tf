# Variables for Wiz Technical Exercise V4 infrastructure (manual deployment phase)

variable "project_id" {
  description = "GCP project ID (e.g. CloudLabs project)"
  type        = string
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for zonal resources (VM, GKE node pool)"
  type        = string
  default     = "us-central1-a"
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
