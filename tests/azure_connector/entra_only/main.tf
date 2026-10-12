provider "azuread" {
  tenant_id = var.tenant_id
}

# Run by a directory administrator with Global Administrator, or Privileged
# Role Administrator plus Application Administrator or Cloud Application
# Administrator. Needs no Azure subscription access. Hand the outputs to the
# operator who runs the arm_only example.
module "azure_connector_entra" {
  source = "../../../modules/azure_connector_entra"

  lead_aws_account_id = var.lead_aws_account_id
  onboarded_accounts  = var.onboarded_accounts
  owner_object_ids    = var.owner_object_ids
}
