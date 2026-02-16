# Outputs for Wiz Technical Exercise V4 (used by app deployment and docs)

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "gke_cluster_name" {
  description = "GKE cluster name for kubectl context"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_subnet_id" {
  description = "Subnet used by GKE (for reference)"
  value       = google_compute_subnetwork.gke.id
}

output "mongodb_vm_name" {
  description = "MongoDB VM instance name"
  value       = google_compute_instance.mongodb.name
}

output "mongodb_vm_internal_ip" {
  description = "MongoDB VM internal IP (use in Kubernetes MONGO_URI)"
  value       = google_compute_instance.mongodb.network_interface[0].network_ip
}

output "mongodb_vm_zone" {
  description = "MongoDB VM zone"
  value       = google_compute_instance.mongodb.zone
}

output "ssh_firewall_name" {
  description = "Name of the SSH-to-VM firewall rule (for lifecycle validation)"
  value       = google_compute_firewall.ssh_to_vm.name
}

output "mongodb_firewall_name" {
  description = "Name of the firewall rule allowing MongoDB (27017) from GKE only (for showcase/validation)"
  value       = google_compute_firewall.mongo_from_gke.name
}

output "mongodb_backup_bucket" {
  description = "GCS bucket name for MongoDB backups"
  value       = google_storage_bucket.mongodb_backups.name
}

# Encode password for URI (same logic as tasky_k8s.tf so output is usable as connection string)
locals {
  mongodb_app_password_uri_encoded = replace(replace(replace(replace(replace(replace(replace(replace(var.mongodb_app_password, "%", "%25"), "/", "%2F"), "?", "%3F"), "#", "%23"), "[", "%5B"), "]", "%5D"), "@", "%40"), ":", "%3A")
}

output "mongodb_connection_string" {
  description = "MongoDB connection string for application (use for tasky_mongodb_uri)"
  value       = "mongodb://${var.mongodb_app_user}:${local.mongodb_app_password_uri_encoded}@${google_compute_instance.mongodb.network_interface[0].network_ip}:27017/tododb"
  sensitive   = true
}

output "mongodb_credentials_path" {
  description = "Path to MongoDB app credentials on the VM (/etc/mongodb-app-credentials.conf)"
  value       = "/etc/mongodb-app-credentials.conf"
}

output "vpc_name" {
  description = "VPC name"
  value       = google_compute_network.vpc.name
}

# --- Artifact Registry (Tasky image pushes) ---

output "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID for Tasky (use in image path)."
  value       = google_artifact_registry_repository.tasky.repository_id
}

output "artifact_registry_repository_url" {
  description = "Artifact Registry repo URL for Docker pushes (e.g. REGION-docker.pkg.dev/PROJECT/REPO)."
  value       = "${coalesce(var.artifact_registry_location, var.region)}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.tasky.repository_id}"
}

# --- Tasky app (when deployed via Terraform Kubernetes provider) ---

output "tasky_namespace" {
  description = "Kubernetes namespace for Tasky app (tasky_enabled or argocd_enabled)"
  value       = try(kubernetes_namespace_v1.tasky[0].metadata[0].name, try(kubernetes_namespace_v1.tasky_argocd[0].metadata[0].name, null))
}

output "tasky_ingress_name" {
  description = "Tasky Ingress resource name; use 'kubectl get ingress -n tasky' for external IP (takes 5–10 min)"
  value       = try(kubernetes_ingress_v1.tasky[0].metadata[0].name, null)
}

# --- Argo CD GitOps (when argocd_enabled = true) ---

output "argocd_namespace" {
  description = "Argo CD namespace (when argocd_enabled = true)"
  value       = var.argocd_enabled ? "argocd" : null
}

output "argocd_application_tasky" {
  description = "Argo CD Application name for Tasky (when argocd_enabled = true)"
  value       = var.argocd_enabled ? "tasky" : null
}
