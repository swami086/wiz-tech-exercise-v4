# VPC and subnets for Wiz Technical Exercise V4
# - Private subnet: GKE (nodes have no public IPs; correct CIDR ranges).
# - Subnet with public access: VM subnet (MongoDB VM has external IP for SSH - intentional).
# Intentional: VM accessible via SSH from internet; GKE control plane has authorized access only.

locals {
  network_name = "${var.environment}-vpc"
  gke_subnet   = "${var.environment}-gke"
  vm_subnet    = "${var.environment}-vm"
}

resource "google_compute_network" "vpc" {
  name                    = local.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Private subnet for GKE (no direct public exposure; secondary ranges for pods/services)
resource "google_compute_subnetwork" "gke" {
  name          = local.gke_subnet
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.gke_subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }

  private_ip_google_access = true
}

# Subnet for MongoDB VM
resource "google_compute_subnetwork" "vm" {
  name          = local.vm_subnet
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.vm_subnet_cidr
}
