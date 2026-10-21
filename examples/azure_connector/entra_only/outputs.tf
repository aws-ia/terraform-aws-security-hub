output "tenant_id" {
  description = "Azure tenant ID. Input to the arm_only example."
  value       = module.azure_connector_entra.tenant_id
}

output "service_principal_object_id" {
  description = "Service principal object ID. Input to the arm_only example."
  value       = module.azure_connector_entra.service_principal_object_id
}

output "application_client_id" {
  description = "Application (client) ID. Input to the arm_only example and to the connector in AWS."
  value       = module.azure_connector_entra.application_client_id
}
