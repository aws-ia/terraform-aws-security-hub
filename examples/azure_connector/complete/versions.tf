terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.9"
    }
  }
}
