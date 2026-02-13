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

output "mongodb_backup_bucket" {
  description = "GCS bucket name for MongoDB backups"
  value       = google_storage_bucket.mongodb_backups.name
}

output "vpc_name" {
  description = "VPC name"
  value       = google_compute_network.vpc.name
}
