# MongoDB VM for Wiz Technical Exercise V4
# Intentional: 1+ year outdated Linux, SSH to public internet, overly permissive IAM.
# MongoDB installation and backup automation are in a separate ticket (MongoDB Setup & Backup Automation).

locals {
  # Use an outdated Debian 10 (buster) image - EOL, qualifies as "1+ year outdated"
  vm_image = "debian-cloud/debian-10-buster-v20220621"
}

# Overly permissive service account for the VM (intentional: "able to create VMs")
resource "google_service_account" "mongodb_vm" {
  account_id   = "mongodb-vm-sa"
  display_name = "MongoDB VM (overly permissive - exercise)"
  project      = var.project_id
}

# Overly permissive: VM can create/manage other VMs (exercise requirement)
resource "google_project_iam_member" "mongodb_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

resource "google_compute_instance" "mongodb" {
  name         = "${var.environment}-mongodb"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-medium"

  tags = [local.vm_network_tag]

  boot_disk {
    initialize_params {
      image = local.vm_image
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vm.self_link
    access_config {} # Intentional: external IP so VM is accessible via SSH from public internet
  }

  service_account {
    email  = google_service_account.mongodb_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    # Block project-wide SSH keys; use IAP or instance-level keys in practice.
    # For exercise we allow SSH via firewall; keys can be added via console or later.
    block-project-ssh-keys = "false"
  }

  allow_stopping_for_update = true
}
