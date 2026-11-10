# The management project is the billing and quota project, so organization
# reads such as Cloud Asset Inventory feeds and organization IAM bill there.
provider "google" {
  project               = var.project_id
  billing_project       = var.project_id
  user_project_override = true
}

provider "google-beta" {
  project               = var.project_id
  billing_project       = var.project_id
  user_project_override = true
}

# Workload identity federation, connector service accounts, organization log
# sinks and Cloud Asset Inventory feeds, Pub/Sub, the organization audit
# configuration, and the Amazon Inspector additions. See the module
# documentation for the permissions that the google provider identity needs.
module "gcp_connector" {
  source = "../../../modules/gcp_connector"

  manage_audit_config    = var.manage_audit_config
  onboarded_accounts     = var.onboarded_accounts
  organization_id        = var.organization_id
  project_id             = var.project_id
  pubsub_kms_key_name    = var.pubsub_kms_key_name
  target_project_ids     = var.target_project_ids
  vm_orchestrator_parent = var.vm_orchestrator_parent
}
