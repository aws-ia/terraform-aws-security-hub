output "accounts" {
  description = "Service account, workload identity provider and audience, topics and sink writer identities of each AWS account."
  value       = module.gcp_connector.accounts
}

output "custom_roles" {
  description = "Custom roles that the module creates."
  value       = module.gcp_connector.custom_roles
}

output "inspector_vm_bridge" {
  description = "Amazon Inspector VM credential bridge pool, provider, audience and minter emails of each account with VM scanning."
  value       = module.gcp_connector.inspector_vm_bridge
}

output "per_account_connector_inputs" {
  description = "Connector inputs for each onboarded account and Region."
  value       = module.gcp_connector.per_account_connector_inputs
}

output "service_agents" {
  description = "Google-managed service agents that the module creates or grants roles to."
  value       = module.gcp_connector.service_agents
}
