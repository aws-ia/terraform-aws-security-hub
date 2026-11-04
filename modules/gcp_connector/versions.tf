terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.50"
    }
    # google_project_service_identity for the Cloud Asset service agent.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.50"
    }
  }
}
