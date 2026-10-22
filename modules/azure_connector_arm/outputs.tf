output "tenant_id" {
  description = "Azure tenant ID that the `azurerm` provider is authenticated to."
  value       = local.tenant_id
}

output "event_hub_resource_group_name" {
  description = "Resource group that holds the Event Hub namespaces."
  value       = azurerm_resource_group.eventhub.name
}

output "event_hub_namespace_name" {
  description = "Name of the shared Event Hub namespace."
  value       = azurerm_eventhub_namespace.shared.name
}

output "event_hub_namespace_fqdn" {
  description = "Fully qualified domain name of the shared Event Hub namespace."
  value       = "${azurerm_eventhub_namespace.shared.name}.servicebus.windows.net"
}

output "regional_acr_namespaces" {
  description = "Regional Event Hub namespaces for container registry events, keyed by location token."
  value = {
    for tok, loc in local.acr_locations_map : tok => {
      location = loc
      fqdn     = "${azurerm_eventhub_namespace.acr[tok].name}.servicebus.windows.net"
      hub      = local.activity_hub_name
    }
  }
}

output "discovery_tags" {
  description = "Tags on the shared namespace that AWS Config and Security Hub use to find the Event Hubs and consumer groups."
  value       = merge(local.config_discovery_tags, local.securityhub_discovery_tags)
}

output "per_account_connector_inputs" {
  description = "Values each onboarded account needs to create its connector, keyed `<aws account>-<aws region>`."
  value = {
    for k, a in local.accounts : k => {
      aws_account_id    = a.aws_account_id
      aws_region        = a.aws_region
      tenant_id         = local.tenant_id
      client_id         = var.application_client_id
      namespace_fqdn    = "${azurerm_eventhub_namespace.shared.name}.servicebus.windows.net"
      activity_hub      = local.activity_hub_name
      config_consumer   = local.activity_consumer_groups[k]
      discovery_tag     = "AWSConfig-${k}"
      defender_hub      = a.enable_threats ? local.defender_hub_name : null
      defender_consumer = a.enable_threats ? "AWSSecurityHub" : null
      acr_namespaces = a.enable_inspector ? {
        for tok, loc in local.acr_locations_map : loc => "${azurerm_eventhub_namespace.acr[tok].name}.servicebus.windows.net"
      } : {}
    }
  }
}

output "policy_assignment_ids" {
  description = "Management group policy assignments created by the module."
  value       = local.policy_assignment_ids
}

output "remediation_subscription_ids" {
  description = "Subscriptions that received provider registrations and compliance scans."
  value       = sort(tolist(local.remediation_subscription_ids))
}
