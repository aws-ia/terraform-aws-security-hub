provider "azurerm" {
  features {}
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "azapi" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

# Run by an Azure administrator with Owner (or Contributor and User Access
# Administrator) at the tenant root management group. Security Administrator is
# also needed for the Entra ID diagnostic setting when CSPM is enabled.
module "azure_connector_arm" {
  source = "../../../modules/azure_connector_arm"

  tenant_id                   = var.tenant_id
  lead_aws_account_id         = var.lead_aws_account_id
  onboarded_accounts          = var.onboarded_accounts
  azure_locations             = var.azure_locations
  service_principal_object_id = var.service_principal_object_id
  application_client_id       = var.application_client_id
}
