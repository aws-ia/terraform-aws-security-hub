locals {
  activity_log_policy_mode = "All"

  activity_log_policy_rule_json = jsonencode({
    "if" = {
      field  = "type"
      equals = "Microsoft.Resources/subscriptions"
    }
    "then" = {
      effect = "DeployIfNotExists"
      details = {
        type            = "Microsoft.Insights/diagnosticSettings"
        name            = "[parameters('profileName')]"
        deploymentScope = "subscription"
        existenceScope  = "subscription"
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
                    { field = "Microsoft.Insights/diagnosticSettings/logs[*].category", equals = "Administrative" },
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
          # Baked in as a literal, NOT a policy parameter: Azure Policy's
          # UnusedPolicyParameters validation rejects a parameter that is only
          # referenced from deployment.location.
          location = var.event_hub_location
          properties = {
            mode = "incremental"
            template = {
              "$schema"      = "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                eventHubAuthorizationRuleId = { type = "string" }
                eventHubName                = { type = "string" }
                profileName                 = { type = "string" }
              }
              resources = [{
                type       = "Microsoft.Insights/diagnosticSettings"
                apiVersion = "2021-05-01-preview"
                name       = "[parameters('profileName')]"
                properties = {
                  eventHubAuthorizationRuleId = "[parameters('eventHubAuthorizationRuleId')]"
                  eventHubName                = "[parameters('eventHubName')]"
                  logs                        = [{ category = "Administrative", enabled = true }]
                }
              }]
            }
            parameters = {
              eventHubAuthorizationRuleId = { value = "[parameters('eventHubAuthorizationRuleId')]" }
              eventHubName                = { value = "[parameters('eventHubName')]" }
              profileName                 = { value = "[parameters('profileName')]" }
            }
          }
        }
      }
    }
  })

  activity_log_policy_parameters_json = jsonencode({
    eventHubAuthorizationRuleId = {
      type = "String"
      metadata = {
        displayName = "Event Hub Authorization Rule Id"
        strongType  = "Microsoft.EventHub/Namespaces/AuthorizationRules"
        # assignPermissions makes the portal grant the assignment identity access
        # to the referenced auth rule.
        assignPermissions = true
      }
    }
    eventHubName = {
      type     = "String"
      metadata = { displayName = "Event Hub Name" }
    }
    profileName = {
      type         = "String"
      metadata     = { displayName = "Profile name" }
      defaultValue = "setByPolicy-EventHub-Administrative"
    }
  })
}

##################################################
# Subscription Activity Log to Event Hub (CSPM and Inspector)
##################################################
# DeployIfNotExists at the root management group: every subscription gets an
# Administrative-category diagnostic setting that sends to the activitylog hub.
# Azure allows 5 Activity Log diagnostic settings per subscription; remediation
# fails for a subscription that already has 5.
resource "azurerm_policy_definition" "activity_log" {
  count = local.enable_activity_policy ? 1 : 0

  name                = local.activity_policy_name
  display_name        = "Activity Logs to Event Hub (AWS ${local.lead_account_id})"
  policy_type         = "Custom"
  mode                = local.activity_log_policy_mode
  management_group_id = local.mg_id
  policy_rule         = local.activity_log_policy_rule_json
  parameters          = local.activity_log_policy_parameters_json
}

resource "azurerm_management_group_policy_assignment" "activity_log" {
  count = local.enable_activity_policy ? 1 : 0

  name                 = local.activity_policy_name
  management_group_id  = local.mg_id
  policy_definition_id = azurerm_policy_definition.activity_log[0].id
  location             = var.event_hub_location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    eventHubAuthorizationRuleId = { value = local.event_hub_auth_rule_id }
    eventHubName                = { value = local.activity_hub_name }
    profileName                 = { value = local.activity_profile_name }
  })

  depends_on = [azurerm_eventhub.activity]
}
