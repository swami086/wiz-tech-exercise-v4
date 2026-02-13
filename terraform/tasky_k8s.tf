# Tasky app deployment via Terraform Kubernetes provider (Wiz Technical Exercise V4).
# Deploys namespace, Secret, RBAC (intentional cluster-admin misconfiguration), Deployment, Service, Ingress.
# Set tasky_enabled = true only after supplying tasky_mongodb_uri and tasky_secret_key; optionally set tasky_image (or use default).
# Build and push image first: ./scripts/build-and-push-tasky.sh

locals {
  tasky_count = var.tasky_enabled ? 1 : 0
  tasky_image = coalesce(var.tasky_image, "${var.region}-docker.pkg.dev/${var.project_id}/tasky-repo/tasky:latest")
}

# --- Namespace ---
resource "kubernetes_namespace_v1" "tasky" {
  count = local.tasky_count

  lifecycle {
    precondition {
      condition     = local.tasky_count == 0 || (length(var.tasky_mongodb_uri) > 0 && length(var.tasky_secret_key) > 0)
      error_message = "When tasky_enabled is true, tasky_mongodb_uri and tasky_secret_key must be non-empty. Enable Tasky only after supplying these values in tfvars or -var."
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
    MONGODB_URI = var.tasky_mongodb_uri
    SECRET_KEY  = var.tasky_secret_key
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
          "tasky/credentials-hash" = substr(sha256("${var.tasky_mongodb_uri}${var.tasky_secret_key}"), 0, 16)
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
