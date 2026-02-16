# Tasky app deployment via Terraform Kubernetes provider (Wiz Technical Exercise V4).
# Deploys namespace, Secret, RBAC (intentional cluster-admin misconfiguration), Deployment, Service, Ingress.
# When tasky_enabled = true: leave tasky_mongodb_uri and tasky_secret_key empty to use Terraform-managed
# MongoDB connection string (from this stack) and a generated JWT secret; or set them to override.
# Build and push image first: ./scripts/build-and-push-tasky.sh

locals {
  tasky_count = var.tasky_enabled ? 1 : 0
  ar_location = coalesce(var.artifact_registry_location, var.region)
  tasky_image = coalesce(var.tasky_image, "${local.ar_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.tasky.repository_id}/tasky:latest")
  # Encode password for URI (e.g. base64 can contain / + = which break parsing)
  mongodb_app_password_encoded = replace(replace(replace(replace(replace(replace(replace(replace(var.mongodb_app_password, "%", "%25"), "/", "%2F"), "?", "%3F"), "#", "%23"), "[", "%5B"), "]", "%5D"), "@", "%40"), ":", "%3A")
  # Derive MongoDB URI from this stack's VM when not overridden (enables destroy/recreate without hardcoded tfvars)
  tasky_mongodb_uri_effective = coalesce(var.tasky_mongodb_uri, "mongodb://${var.mongodb_app_user}:${local.mongodb_app_password_encoded}@${google_compute_instance.mongodb.network_interface[0].network_ip}:27017/tododb")
  tasky_secret_key_effective  = var.tasky_enabled ? (length(var.tasky_secret_key) > 0 ? var.tasky_secret_key : random_password.tasky_jwt[0].result) : ""
}

# Generated JWT secret when tasky_enabled and tasky_secret_key is not set (so destroy/recreate needs no tfvars)
resource "random_password" "tasky_jwt" {
  count = local.tasky_count

  length  = 32
  special = true
}

# --- Namespace ---
resource "kubernetes_namespace_v1" "tasky" {
  count = local.tasky_count

  lifecycle {
    precondition {
      condition     = local.tasky_count == 0 || (length(local.tasky_mongodb_uri_effective) > 0 && length(local.tasky_secret_key_effective) >= 32)
      error_message = "When tasky_enabled is true, either leave tasky_mongodb_uri and tasky_secret_key empty (Terraform will derive/generate) or set both with at least 32-char secret."
    }
  }

  metadata {
    name   = "tasky"
    labels = { app = "tasky" }
  }
}

# --- Secret (MONGODB_URI, SECRET_KEY) ---
resource "kubernetes_secret_v1" "tasky_secret" {
  count = local.tasky_count

  metadata {
    name      = "tasky-secret"
    namespace = kubernetes_namespace_v1.tasky[0].metadata[0].name
    labels    = { app = "tasky" }
  }

  # Provider base64-encodes automatically; do not double-encode or the pod receives base64 string instead of URI
  data = {
    MONGODB_URI = local.tasky_mongodb_uri_effective
    SECRET_KEY  = local.tasky_secret_key_effective
  }

  type = "Opaque"
}

# --- RBAC: ServiceAccount + ClusterRoleBinding to cluster-admin (intentional misconfiguration) ---
# SA name "tasky" per spec so: kubectl auth can-i '*' '*' --as=system:serviceaccount:tasky:tasky
resource "kubernetes_service_account_v1" "tasky" {
  count = local.tasky_count

  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace_v1.tasky[0].metadata[0].name
    labels    = { app = "tasky" }
  }
}

resource "kubernetes_cluster_role_binding_v1" "tasky_admin" {
  count = local.tasky_count

  metadata {
    name   = "tasky-cluster-admin"
    labels = { app = "tasky" }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.tasky[0].metadata[0].name
    namespace = kubernetes_service_account_v1.tasky[0].metadata[0].namespace
  }
}

# --- Deployment ---
resource "kubernetes_deployment_v1" "tasky" {
  count = local.tasky_count

  wait_for_rollout = false # avoid apply blocking on pod rollout (pods can take time to become ready)

  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace_v1.tasky[0].metadata[0].name
    labels    = { app = "tasky" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "tasky" }
    }

    template {
      metadata {
        labels = { app = "tasky" }
        # Change when credentials change so pods roll and pick up new secret
        annotations = {
          "tasky/credentials-hash" = substr(sha256("${local.tasky_mongodb_uri_effective}${local.tasky_secret_key_effective}"), 0, 16)
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.tasky[0].metadata[0].name
        automount_service_account_token = true

        container {
          name              = "tasky"
          image             = local.tasky_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name = "MONGODB_URI"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.tasky_secret[0].metadata[0].name
                key  = "MONGODB_URI"
              }
            }
          }
          env {
            name = "SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.tasky_secret[0].metadata[0].name
                key  = "SECRET_KEY"
              }
            }
          }

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "500m"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["kubectl.kubernetes.io/restartedAt"]
    ]
  }
}

# --- Service (ClusterIP) ---
resource "kubernetes_service_v1" "tasky" {
  count = local.tasky_count

  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace_v1.tasky[0].metadata[0].name
    labels    = { app = "tasky" }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "tasky"
    }

    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# --- Ingress (GCP HTTP(S) Load Balancer; external IP may take 5–10 min) ---
resource "kubernetes_ingress_v1" "tasky" {
  count = local.tasky_count

  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace_v1.tasky[0].metadata[0].name
    labels    = { app = "tasky" }

    annotations = {
      "kubernetes.io/ingress.class" = "gce"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "ImplementationSpecific"

          backend {
            service {
              name = kubernetes_service_v1.tasky[0].metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
