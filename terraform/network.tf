# VPC and subnets for Wiz Technical Exercise V4
# - Private subnet: GKE (nodes have no public IPs; correct CIDR ranges).
# - Subnet with public access: VM subnet (MongoDB VM has external IP for SSH - intentional).
# Intentional: VM accessible via SSH from internet; GKE control plane has authorized access only.
#
# Cloud NAT (below) is REQUIRED for private GKE nodes to reach the internet (quay.io for Argo CD,
# Docker Hub, GCR, etc.). Without NAT, Argo CD and other workloads will hit ImagePullBackOff.
# Creation order: VPC → subnets → router → NAT → GKE. terraform destroy + apply recreates all.

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

# Cloud NAT for private GKE nodes: outbound internet for image pulls (Argo CD, Tasky, etc.).
# Included in standard apply (no -target). Destroy removes router and NAT with the rest of the stack.
resource "google_compute_router" "vpc" {
  name    = "${var.environment}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "vpc" {
  name                               = "${var.environment}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.vpc.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
