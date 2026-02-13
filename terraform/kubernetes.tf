# Kubernetes provider for GKE (Application Deployment via Terraform Kubernetes Provider).
# Uses GKE cluster endpoint and credentials from this Terraform run.
# Ensure the GKE cluster exists before first apply of Kubernetes resources (tasky_enabled = true).
# See: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#stacking-with-managed-kubernetes-cluster-resources

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)

  # GKE adds annotations/labels; ignore so Terraform does not remove them
  ignore_annotations = [
    "^cloud\\.google\\.com/.*",
    "^autopilot\\.gke\\.io/.*",
    "^run\\.googleapis\\.com/.*"
  ]
  ignore_labels = [
    "^cloud\\.google\\.com/.*"
  ]
}
