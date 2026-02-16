# Organization Policy: Require OS Login (GCP Security Tooling ticket)
# Preventative control: enforces OS Login for VM SSH (works with IAP tunnel).
# SSH via gcloud compute ssh --tunnel-through-iap remains valid.
# Set enable_require_os_login = false if the principal lacks orgpolicy.policyAdmin (e.g. CloudLabs); set policy manually in Console.

resource "google_project_organization_policy" "require_os_login" {
  count      = var.enable_require_os_login ? 1 : 0
  project    = var.project_id
  constraint = "constraints/compute.requireOsLogin"

  boolean_policy {
    enforced = true
  }
}
