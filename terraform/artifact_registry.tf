# Artifact Registry repository for Tasky container images (Wiz Technical Exercise V4).
# Ensures the repo exists before Tasky deployment and image pushes.

resource "google_project_service" "artifactregistry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
}

resource "google_artifact_registry_repository" "tasky" {
  project       = var.project_id
  location      = coalesce(var.artifact_registry_location, var.region)
  repository_id = var.artifact_registry_repository_id
  format        = var.artifact_registry_format
  description   = "Tasky application container images for Wiz Exercise"
  depends_on    = [google_project_service.artifactregistry]
}
