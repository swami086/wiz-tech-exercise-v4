# GCS bucket for MongoDB backups - Wiz Technical Exercise V4
# Intentional misconfiguration: public read and public listing for entire bucket (required by exercise).

locals {
  backup_bucket_name = coalesce(
    var.backup_bucket_name,
    "${var.project_id}-mongodb-backups-${var.environment}"
  )
}

resource "google_storage_bucket" "mongodb_backups" {
  name          = local.backup_bucket_name
  project       = var.project_id
  location      = var.region
  force_destroy = true # allow destroy to delete bucket with objects (e.g. clean recreate)

  # Uniform bucket-level access (required for IAM-based public access)
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Lifecycle optional: delete old backups after N days (uncomment if desired)
  # lifecycle_rule { ... }
}

# Intentional misconfiguration (exercise): public read + listing.
# Project override applied via: gcloud org-policies set-policy org-policy-allow-public-bucket.yaml --project=wizdemo-487311
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "public_list" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.legacyBucketReader"
  member = "allUsers"
}

# MongoDB VM service account can write backups (objectCreator) to this bucket
resource "google_storage_bucket_iam_member" "mongodb_vm_backup_writer" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.mongodb_vm.email}"
}
