output "tenant_id" {
  description = "Azure tenant ID that the `azuread` provider is authenticated to."
  value       = local.tenant_id
}

output "application_object_id" {
  description = "Object ID of the Entra application registration."
  value       = azuread_application.connector.object_id
}

output "application_client_id" {
  description = "Application (client) ID of the Entra application registration. Required when you create the connector in AWS."
  value       = azuread_application.connector.client_id
}

output "application_display_name" {
  description = "Display name of the Entra application registration."
  value       = azuread_application.connector.display_name
}

output "identifier_uri" {
  description = "Application ID URI, `api://<client id>`."
  value       = azuread_application_identifier_uri.connector.identifier_uri
}

output "service_principal_object_id" {
  description = "Object ID of the service principal. Pass it to the `azure_connector_arm` module."
  value       = azuread_service_principal.connector.object_id
}

output "federated_credentials" {
  description = "Federated identity credentials on the application, keyed `<aws account>-<purpose>`."
  value = {
    for k, v in azuread_application_federated_identity_credential.aws : k => {
      display_name = v.display_name
      issuer       = v.issuer
      subject      = v.subject
    }
  }
}

output "graph_permissions" {
  description = "Microsoft Graph application permissions granted to the service principal."
  value       = sort(keys(azuread_app_role_assignment.graph))
}
