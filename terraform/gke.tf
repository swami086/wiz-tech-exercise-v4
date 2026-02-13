# GKE cluster for Wiz Technical Exercise V4
# Intentional design: private nodes (no direct public exposure); control plane accessible from laptop via authorized networks only.
# Uses a dedicated node SA to avoid depending on the default Compute Engine SA (which may not exist in some projects).

resource "google_service_account" "gke_node" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Pool (Wiz Exercise)"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_node_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_container_cluster" "primary" {
  provider = google-beta

  name     = "${var.environment}-gke"
  project  = var.project_id
  location = var.region

  # Use our VPC and subnet; remove default node pool so we create a custom one
  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.gke.self_link

  remove_default_node_pool = true
  initial_node_count       = 1

  # IP allocation for VPC-native cluster (pods and services)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster: nodes have private IPs only (in private subnet)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Keep public endpoint so we can use kubectl without bastion
    master_ipv4_cidr_block  = var.gke_master_cidr
  }

  # Kubernetes control plane: accessible from your laptop via authorized networks (restrict further in production)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Authorized access (demo)"
    }
  }

  # Enable workload identity for later (optional)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Logging and monitoring (required for Security Command Center / audit)
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  deletion_protection = false
}

# Separate node pool for clearer control
resource "google_container_node_pool" "primary" {
  name       = "${var.environment}-np"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    machine_type    = var.gke_node_machine_type
    disk_size_gb    = 20
    service_account = google_service_account.gke_node.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
    }

    tags = ["gke-node", "${var.environment}-gke"]
  }
}
