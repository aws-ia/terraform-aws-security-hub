output "per_account_connector_inputs" {
  description = "Connector inputs for each onboarded account and Region."
  value       = module.azure_connector_arm.per_account_connector_inputs
}

output "remediation_subscription_ids" {
  description = "Subscriptions that received provider registrations and compliance scans."
  value       = module.azure_connector_arm.remediation_subscription_ids
}
