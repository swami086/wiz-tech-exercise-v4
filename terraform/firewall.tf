# Firewall rules for Wiz Technical Exercise V4
# Intentional: SSH to MongoDB VM from 0.0.0.0/0 (required by exercise).
# MongoDB (27017) allowed only from GKE subnet and pod range.

locals {
  vm_network_tag = "mongodb-vm"
}

# SSH from anywhere to MongoDB VM (intentional misconfiguration for exercise)
resource "google_compute_firewall" "ssh_to_vm" {
  name    = "${var.environment}-allow-ssh-vm"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.vm_network_tag]
}

# MongoDB (27017) from GKE nodes and pods only
resource "google_compute_firewall" "mongo_from_gke" {
  name    = "${var.environment}-allow-mongo-from-gke"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  source_ranges = [
    var.gke_subnet_cidr,
    "10.1.0.0/16" # GKE pods secondary range
  ]
  target_tags = [local.vm_network_tag]
}

# Allow egress from GKE nodes (e.g. pull images, reach VM)
# Default implied allow for egress; explicit rule for clarity if needed.
# GKE creates its own firewall rules; we only add VM-facing rules here.
