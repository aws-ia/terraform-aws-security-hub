locals {
  acr_diagnostics_policy_mode = "Indexed"

  acr_diagnostics_policy_rule_json = jsonencode({
    "if" = {
      allOf = [
        { field = "type", equals = "Microsoft.ContainerRegistry/registries" },
        { field = "location", equals = "[parameters('eventHubLocation')]" },
      ]
    }
    "then" = {
      effect = "DeployIfNotExists"
      # details.name is deliberately omitted, so the existenceCondition is evaluated
      # against every diagnostic setting on the registry: any setting that already
      # forwards repository events to this account's hub satisfies it, whatever its
      # name. Remediation deploys under the account-suffixed profileName, so
      # deployments sharing a subscription each get their own setting instead of
      # re-pointing one shared setting. Pinning the name
      # would make remediation create a second setting to the same Event Hub, which
      # Azure rejects.
      details = {
        type = "Microsoft.Insights/diagnosticSettings"
        existenceCondition = {
          allOf = [
            {
              field  = "Microsoft.Insights/diagnosticSettings/eventHubAuthorizationRuleId"
              equals = "[parameters('eventHubAuthorizationRuleId')]"
            },
            {
              field  = "Microsoft.Insights/diagnosticSettings/eventHubName"
              equals = "[parameters('eventHubName')]"
            },
            {
              count = {
                field = "Microsoft.Insights/diagnosticSettings/logs[*]"
                where = {
                  allOf = [
                    { field = "Microsoft.Insights/diagnosticSettings/logs[*].category", equals = "ContainerRegistryRepositoryEvents" },
                    { field = "Microsoft.Insights/diagnosticSettings/logs[*].enabled", equals = "true" },
                  ]
                }
              }
              equals = 1
            },
          ]
        }
        roleDefinitionIds = [local.contributor_role_definition_id]
        deployment = {
          # No explicit location here: the deployment inherits the assignment's.
          properties = {
            mode = "incremental"
            template = {
              "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                resourceName                = { type = "string" }
                eventHubAuthorizationRuleId = { type = "string" }
                eventHubName                = { type = "string" }
                profileName                 = { type = "string" }
              }
              resources = [{
                type       = "Microsoft.ContainerRegistry/registries/providers/diagnosticSettings"
                apiVersion = "2021-05-01-preview"
                name       = "[concat(parameters('resourceName'), '/Microsoft.Insights/', parameters('profileName'))]"
                properties = {
                  eventHubAuthorizationRuleId = "[parameters('eventHubAuthorizationRuleId')]"
                  eventHubName                = "[parameters('eventHubName')]"
                  logs                        = [{ category = "ContainerRegistryRepositoryEvents", enabled = true }]
                }
              }]
            }
            parameters = {
              resourceName                = { value = "[field('name')]" }
              eventHubAuthorizationRuleId = { value = "[parameters('eventHubAuthorizationRuleId')]" }
              eventHubName                = { value = "[parameters('eventHubName')]" }
              profileName                 = { value = "[parameters('profileName')]" }
            }
          }
        }
      }
    }
  })

  acr_diagnostics_policy_parameters_json = jsonencode({
    eventHubAuthorizationRuleId = {
      type = "String"
      metadata = {
        displayName       = "Event Hub Authorization Rule Id"
        strongType        = "Microsoft.EventHub/Namespaces/AuthorizationRules"
        assignPermissions = true
      }
    }
    eventHubName = {
      type     = "String"
      metadata = { displayName = "Event Hub Name" }
    }
    eventHubLocation = {
      type = "String"
      metadata = {
        displayName = "Event Hub Location"
        description = "Only ACRs in this region are evaluated; pairs them to a same-region Event Hub."
        strongType  = "location"
      }
      defaultValue = "eastus"
    }
    profileName = {
      type         = "String"
      metadata     = { displayName = "Profile name" }
      defaultValue = "setByPolicy-EventHub-ContainerRegistryRepositoryEvents"
    }
  })
}

##################################################
# ACR repository events to same-location Event Hub (Inspector)
##################################################
# One definition, one assignment per location. A single assignment that looks
# up a per-location rule with [field('location')] fails assignment validation.
resource "azurerm_policy_definition" "acr_diagnostics" {
  count = local.any_inspector ? 1 : 0

  name                = local.acr_policy_name
  display_name        = "ACR Diagnostics to Event Hub (AWS ${local.lead_account_id})"
  policy_type         = "Custom"
  mode                = local.acr_diagnostics_policy_mode
  management_group_id = local.mg_id
  policy_rule         = local.acr_diagnostics_policy_rule_json
  parameters          = local.acr_diagnostics_policy_parameters_json
}

# The managed identity is created in the registry's location, so the
# deployment runs there.
resource "azurerm_management_group_policy_assignment" "acr_diagnostics" {
  for_each = local.acr_locations_map

  name                 = "${local.acr_policy_name}-${each.key}"
  management_group_id  = local.mg_id
  policy_definition_id = azurerm_policy_definition.acr_diagnostics[0].id
  location             = each.value

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    eventHubAuthorizationRuleId = { value = "${azurerm_eventhub_namespace.acr[each.key].id}/authorizationrules/RootManageSharedAccessKey" }
    eventHubName                = { value = local.activity_hub_name }
    eventHubLocation            = { value = each.value }
    profileName                 = { value = local.acr_profile_name }
  })

  depends_on = [azurerm_eventhub.acr_activity]
}
