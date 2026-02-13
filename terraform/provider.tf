# GCP provider for Wiz Technical Exercise V4

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Kubernetes provider is in terraform/kubernetes.tf (Application Deployment via Terraform Kubernetes Provider).
