output "accounts" {
  description = "Service account, workload identity provider and audience, topics and sink writer identities of each AWS account."
  value       = module.gcp_connector.accounts
}

output "custom_roles" {
  description = "Custom roles that the module creates."
  value       = module.gcp_connector.custom_roles
}

output "per_account_connector_inputs" {
  description = "Connector inputs for each onboarded account and Region."
  value       = module.gcp_connector.per_account_connector_inputs
}

output "service_agents" {
  description = "Google-managed service agents that the module creates or grants roles to."
  value       = module.gcp_connector.service_agents
}
