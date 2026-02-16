# Argo CD GitOps deployment (Wiz Technical Exercise V4).
# When argocd_enabled=true: installs Argo CD, creates tasky namespace+secret, and an Application
# that syncs the Tasky app from kubernetes/ in the Git repo.
# Set tasky_enabled=false when using argocd_enabled to avoid conflicting deployments.
#
# Destroy/recreate: terraform destroy removes null_resources from state; terraform apply
# recreates cluster → Argo CD install (--server-side --force-conflicts for CRD limits) → Application.
# Cloud NAT (network.tf) must exist for private GKE nodes to pull Argo CD images from quay.io.

locals {
  argocd_count = var.argocd_enabled ? 1 : 0
  # Reuse artifact registry location for Tasky image
  argocd_ar_location = coalesce(var.artifact_registry_location, var.region)
  argocd_tasky_image = coalesce(var.tasky_image, "${local.argocd_ar_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.tasky.repository_id}/tasky:latest")
  # MongoDB URI and secret key (same derivation as tasky_k8s when not overridden)
  argocd_mongodb_password_encoded = replace(replace(replace(replace(replace(replace(replace(replace(var.mongodb_app_password, "%", "%25"), "/", "%2F"), "?", "%3F"), "#", "%23"), "[", "%5B"), "]", "%5D"), "@", "%40"), ":", "%3A")
  argocd_mongodb_uri              = coalesce(var.tasky_mongodb_uri, "mongodb://${var.mongodb_app_user}:${local.argocd_mongodb_password_encoded}@${google_compute_instance.mongodb.network_interface[0].network_ip}:27017/tododb")
  # When argocd_enabled=false do not reference random_password.argocd_tasky_jwt (count=0, so [0] would be empty tuple). Only reference it in the true branch.
  argocd_secret_key               = var.argocd_enabled ? (length(trimspace(var.tasky_secret_key)) > 0 ? var.tasky_secret_key : random_password.argocd_tasky_jwt[0].result) : ""
}

resource "random_password" "argocd_tasky_jwt" {
  count = local.argocd_count

  length  = 32
  special = true
}

resource "kubernetes_namespace_v1" "tasky_argocd" {
  count = local.argocd_count

  lifecycle {
    precondition {
      condition     = !var.argocd_enabled || !var.tasky_enabled
      error_message = "Set tasky_enabled=false when argocd_enabled=true (use either Terraform-managed Tasky or Argo CD GitOps, not both)."
    }
    precondition {
      condition     = !var.argocd_enabled || (length(var.argocd_git_repo_url) > 0 && length(local.argocd_mongodb_uri) > 0 && length(local.argocd_secret_key) >= 32)
      error_message = "When argocd_enabled=true: set argocd_git_repo_url; leave tasky_mongodb_uri/tasky_secret_key empty for auto-derivation or set both (secret ≥32 chars)."
    }
  }

  metadata {
    name   = "tasky"
    labels = { app = "tasky" }
  }
}

resource "kubernetes_secret_v1" "tasky_argocd" {
  count = local.argocd_count

  metadata {
    name      = "tasky-secret"
    namespace = kubernetes_namespace_v1.tasky_argocd[0].metadata[0].name
    labels    = { app = "tasky" }
  }

  data = {
    MONGODB_URI = local.argocd_mongodb_uri
    SECRET_KEY  = local.argocd_secret_key
  }

  type = "Opaque"
}

# Install Argo CD via kubectl (cluster must exist and be accessible)
resource "null_resource" "argocd_install" {
  count = local.argocd_count

  triggers = {
    cluster = google_container_cluster.primary.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${google_container_cluster.primary.name} \
        --region ${google_container_cluster.primary.location} \
        --project ${var.project_id}
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
    EOT
    environment = {
      CLOUDSDK_CORE_PROJECT = var.project_id
    }
  }

  depends_on = [kubernetes_namespace_v1.tasky_argocd]
}

# Apply Argo CD Application after install (CRD not available at plan time)
resource "null_resource" "argocd_application_tasky" {
  count = local.argocd_count

  triggers = {
    repo_url     = var.argocd_git_repo_url
    git_revision = var.argocd_git_revision
    tasky_image  = local.argocd_tasky_image
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      gcloud container clusters get-credentials ${google_container_cluster.primary.name} \
        --region ${google_container_cluster.primary.location} \
        --project ${var.project_id}
      TMPF=$(mktemp)
      cat > "$TMPF" << 'ARGOCD_APP'
${templatefile("${path.module}/argocd-application.yaml.tpl", {
    repo_url     = var.argocd_git_repo_url
    git_revision = var.argocd_git_revision
    tasky_image  = local.argocd_tasky_image
})}
ARGOCD_APP
      kubectl apply -n argocd -f "$TMPF"
      rm -f "$TMPF"
    EOT
}

depends_on = [null_resource.argocd_install]
}
