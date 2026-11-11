terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.50"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.27"
    }
  }
}
