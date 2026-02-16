# Cloud Monitoring detective controls (GCP Security Tooling ticket)
# Alerts on security-relevant events: firewall changes, storage bucket IAM changes.

# Log-based metric: firewall rule create/update/delete (audit log)
resource "google_logging_metric" "firewall_change" {
  name        = "wiz_exercise_firewall_change"
  description = "Audit events for Compute Engine firewall insert/patch/delete"
  project     = var.project_id
  filter      = <<-EOT
    protoPayload.serviceName="compute.googleapis.com"
    (protoPayload.methodName="v1.compute.firewalls.insert"
     OR protoPayload.methodName="v1.compute.firewalls.patch"
     OR protoPayload.methodName="v1.compute.firewalls.delete")
  EOT
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Log-based metric: storage bucket IAM or public access (SetIamPolicy on bucket)
resource "google_logging_metric" "storage_bucket_iam_change" {
  name        = "wiz_exercise_storage_bucket_iam_change"
  description = "Audit events for Storage bucket IAM changes (e.g. public access)"
  project     = var.project_id
  filter      = <<-EOT
    protoPayload.serviceName="storage.googleapis.com"
    protoPayload.methodName="storage.buckets.setIamPolicy"
  EOT
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Alert policy: firewall rule changes (detective control); gated so automation SA need not have alert roles by default
resource "google_monitoring_alert_policy" "firewall_change" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  project      = var.project_id
  display_name = "[Wiz Exercise] Firewall rule create/update/delete"
  combiner     = "OR"

  lifecycle {
    precondition {
      condition     = !var.enable_monitoring_alerts || length(trimspace(var.alert_notification_email)) > 0
      error_message = "When enable_monitoring_alerts is true, alert_notification_email must be non-empty. Set a valid email in terraform.tfvars for alert notifications."
    }
  }

  conditions {
    display_name = "Firewall change detected"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.firewall_change.name}\" AND resource.type=\"global\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "This alert fires when a Compute Engine firewall rule is created, updated, or deleted (audit log). Part of Wiz Exercise detective controls."
  }

  notification_channels = var.alert_notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
}

# Alert policy: storage bucket IAM changes (e.g. public bucket); gated so automation SA need not have alert roles by default
resource "google_monitoring_alert_policy" "storage_bucket_iam_change" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  project      = var.project_id
  display_name = "[Wiz Exercise] Storage bucket IAM change"
  combiner     = "OR"

  conditions {
    display_name = "Bucket IAM change detected"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.storage_bucket_iam_change.name}\" AND resource.type=\"global\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "This alert fires when a Storage bucket IAM policy is set (e.g. public access). Part of Wiz Exercise detective controls."
  }

  notification_channels = var.alert_notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
}

# Optional: email notification channel (created only when monitoring alerts enabled and email set)
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring_alerts && var.alert_notification_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "Wiz Exercise Alerts"
  type         = "email"
  labels = {
    email_address = var.alert_notification_email
  }
}
