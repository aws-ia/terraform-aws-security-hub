terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.50"
    }
    # google_project_service_identity and google_organization_service_identity.
    # google-beta 7.27.0 added google_organization_service_identity.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.27"
    }
  }
}
