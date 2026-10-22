provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azurerm" {
  features {}
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "azapi" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

# Entra ID: application registration, service principal, federated credentials
# and Microsoft Graph admin consent. Needs Global Administrator, or Privileged
# Role Administrator plus Application Administrator or Cloud Application
# Administrator.
module "azure_connector_entra" {
  source = "../../../modules/azure_connector_entra"

  lead_aws_account_id = var.lead_aws_account_id
  onboarded_accounts  = var.onboarded_accounts
  owner_object_ids    = var.owner_object_ids
}

# Azure Resource Manager: Event Hubs, policies, role assignments and
# remediation. Needs Owner (or Contributor and User Access Administrator) at the
# tenant root management group, and Security Administrator for the Entra ID
# diagnostic setting.
module "azure_connector_arm" {
  source = "../../../modules/azure_connector_arm"

  lead_aws_account_id         = var.lead_aws_account_id
  onboarded_accounts          = var.onboarded_accounts
  azure_locations             = var.azure_locations
  tenant_id                   = module.azure_connector_entra.tenant_id
  service_principal_object_id = module.azure_connector_entra.service_principal_object_id
  application_client_id       = module.azure_connector_entra.application_client_id

  tags = {
    Environment = "test"
  }
}
