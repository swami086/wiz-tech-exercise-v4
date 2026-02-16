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
    # No access_config: VM has no external IP; use IAP tunnel for SSH (e.g. gcloud compute ssh --tunnel-through-iap).
    # MongoDB (27017) is reachable only from GKE subnet per firewall rules.
  }

  service_account {
    email  = google_service_account.mongodb_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    # Block project-wide SSH keys; use IAP or instance-level keys in practice.
    # For exercise we allow SSH via firewall; keys can be added via console or later.
    block-project-ssh-keys = "false"
    # Used by MongoDB setup/backup docs and scripts
    mongodb-backup-bucket = google_storage_bucket.mongodb_backups.name
  }

  # Automated MongoDB 4.4 install, auth, tododb, and daily backup cron on first boot
  metadata_startup_script = templatefile("${path.module}/scripts/mongodb-startup.sh.tpl", {
    gcs_backup_bucket    = google_storage_bucket.mongodb_backups.name
    mongo_admin_user     = var.mongodb_admin_user
    mongo_admin_password = var.mongodb_admin_password
    mongo_app_user       = var.mongodb_app_user
    mongo_app_password   = var.mongodb_app_password
  })

  allow_stopping_for_update = true
}
