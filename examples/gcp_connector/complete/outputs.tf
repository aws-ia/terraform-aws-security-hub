output "accounts" {
  description = "Service account and workload identity provider of each AWS account."
  value       = module.gcp_connector.accounts
}

output "per_account_connector_inputs" {
  description = "Connector inputs for each onboarded account and Region."
  value       = module.gcp_connector.per_account_connector_inputs
}
