output "application_client_id" {
  description = "Application (client) ID to enter when you create the connector in AWS."
  value       = module.azure_connector_entra.application_client_id
}

output "tenant_id" {
  description = "Azure tenant ID."
  value       = module.azure_connector_entra.tenant_id
}

output "per_account_connector_inputs" {
  description = "Connector inputs for each onboarded account and Region."
  value       = module.azure_connector_arm.per_account_connector_inputs
}
