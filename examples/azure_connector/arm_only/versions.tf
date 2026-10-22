terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.9"
    }
  }
}
