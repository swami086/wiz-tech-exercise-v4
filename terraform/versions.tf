# Terraform and provider version constraints for Wiz Technical Exercise V4

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }

  backend "gcs" {
    # Bucket and prefix set via -backend-config or backend config file.
    # Example: -backend-config="bucket=PROJECT_ID-tfstate-wiz-exercise"
    #          -backend-config="prefix=terraform/state"
  }
}
