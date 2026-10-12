locals {
  defender_export_policy_mode = "All"

  defender_export_policy_rule_json = jsonencode({
    "if" = {
      field  = "type"
      equals = "Microsoft.Resources/subscriptions"
    }
    "then" = {
      effect = "deployIfNotExists"
      details = {
        type              = "Microsoft.Security/automations"
        name              = "[parameters('automationName')]"
        existenceScope    = "resourceGroup"
        resourceGroupName = "[parameters('deploymentResourceGroupName')]"
        deploymentScope   = "subscription"
        # Without this, existence is judged by resource name alone, so an
        # automation that is disabled, or that exports to a different Event Hub,
        # counts as compliant and is never repaired.
        existenceCondition = {
          allOf = [
            {
              field  = "Microsoft.Security/automations/isEnabled"
              equals = "true"
            },
            {
              count = {
                field = "Microsoft.Security/automations/scopes[*]"
              }
              equals = 1
            },
            {
              count = {
                field = "Microsoft.Security/automations/scopes[*]"
                where = {
                  field  = "Microsoft.Security/automations/scopes[*].scopePath"
                  equals = "[subscription().id]"
                }
              }
              equals = 1
            },
            {
              count = {
                field = "Microsoft.Security/automations/sources[*]"
              }
              equals = 1
            },
            {
              count = {
                field = "Microsoft.Security/automations/sources[*]"
                where = {
                  field  = "Microsoft.Security/automations/sources[*].eventSource"
                  equals = "Alerts"
                }
              }
              equals = 1
            },
            {
              count = {
                field = "Microsoft.Security/automations/sources[*].ruleSets[*]"
              }
              equals = 0
            },
            {
              count = {
                field = "Microsoft.Security/automations/actions[*]"
              }
              equals = 1
            },
            {
              count = {
                field = "Microsoft.Security/automations/actions[*]"
                where = {
                  allOf = [
                    {
                      field  = "Microsoft.Security/automations/actions[*].actionType"
                      equals = "EventHub"
                    },
                    {
                      field  = "Microsoft.Security/automations/actions[*].EventHub.eventHubResourceId"
                      equals = "[concat(parameters('eventHubNamespaceResourceId'), '/eventhubs/', parameters('eventHubName'))]"
                    },
                    {
                      field  = "Microsoft.Security/automations/actions[*].EventHub.sasPolicyName"
                      equals = "[parameters('sasPolicyName')]"
                    },
                  ]
                }
              }
              equals = 1
            },
          ]
        }
        roleDefinitionIds = [local.contributor_role_definition_id]
        deployment = {
          # A literal, not "[parameters('deploymentLocation')]": Azure Policy's
          # UnusedPolicyParameters validation rejects a parameter that is only
          # referenced from deployment.location.
          location = var.event_hub_location
          properties = {
            mode                        = "incremental"
            expressionEvaluationOptions = { scope = "outer" }
            parameters = {
              eventHubNamespaceResourceId = { value = "[parameters('eventHubNamespaceResourceId')]" }
              eventHubName                = { value = "[parameters('eventHubName')]" }
              eventHubAuthorizationRuleId = { value = "[parameters('eventHubAuthorizationRuleId')]" }
              sasPolicyName               = { value = "[parameters('sasPolicyName')]" }
              deploymentResourceGroupName = { value = "[parameters('deploymentResourceGroupName')]" }
              deploymentLocation          = { value = "[parameters('deploymentLocation')]" }
              automationName              = { value = "[parameters('automationName')]" }
            }
            template = {
              "$schema"      = "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                eventHubNamespaceResourceId = { type = "string" }
                eventHubName                = { type = "string" }
                eventHubAuthorizationRuleId = { type = "string" }
                sasPolicyName               = { type = "string" }
                deploymentResourceGroupName = { type = "string" }
                deploymentLocation          = { type = "string" }
                automationName              = { type = "string" }
              }
              resources = [
                {
                  type       = "Microsoft.Resources/resourceGroups"
                  apiVersion = "2021-04-01"
                  name       = "[parameters('deploymentResourceGroupName')]"
                  location   = "[parameters('deploymentLocation')]"
                  properties = {}
                },
                {
                  type          = "Microsoft.Resources/deployments"
                  apiVersion    = "2021-04-01"
                  name          = "deploy-securityhub-defender-automation"
                  resourceGroup = "[parameters('deploymentResourceGroupName')]"
                  dependsOn = [
                    "[resourceId('Microsoft.Resources/resourceGroups', parameters('deploymentResourceGroupName'))]",
                  ]
                  properties = {
                    mode                        = "Incremental"
                    expressionEvaluationOptions = { scope = "inner" }
                    parameters = {
                      eventHubNamespaceResourceId = { value = "[parameters('eventHubNamespaceResourceId')]" }
                      eventHubName                = { value = "[parameters('eventHubName')]" }
                      eventHubAuthorizationRuleId = { value = "[parameters('eventHubAuthorizationRuleId')]" }
                      sasPolicyName               = { value = "[parameters('sasPolicyName')]" }
                      deploymentLocation          = { value = "[parameters('deploymentLocation')]" }
                      automationName              = { value = "[parameters('automationName')]" }
                    }
                    template = {
                      "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
                      contentVersion = "1.0.0.0"
                      parameters = {
                        eventHubNamespaceResourceId = { type = "string" }
                        eventHubName                = { type = "string" }
                        eventHubAuthorizationRuleId = { type = "string" }
                        sasPolicyName               = { type = "string" }
                        deploymentLocation          = { type = "string" }
                        automationName              = { type = "string" }
                      }
                      variables = {
                        eventHubResourceId = "[concat(parameters('eventHubNamespaceResourceId'), '/eventhubs/', parameters('eventHubName'))]"
                      }
                      resources = [{
                        type       = "Microsoft.Security/automations"
                        apiVersion = "2019-01-01-preview"
                        name       = "[parameters('automationName')]"
                        location   = "[parameters('deploymentLocation')]"
                        properties = {
                          description = "Exports Microsoft Defender for Cloud alerts to the SecurityHub MultiCloud Event Hub."
                          isEnabled   = true
                          scopes = [{
                            description = "Subscription scope"
                            scopePath   = "[subscription().id]"
                          }]
                          sources = [{
                            eventSource = "Alerts"
                            ruleSets    = []
                          }]
                          actions = [{
                            actionType         = "EventHub"
                            eventHubResourceId = "[variables('eventHubResourceId')]"
                            # Resolved at deploy time, deliberately never a
                            # stored literal.
                            connectionString = "[listKeys(parameters('eventHubAuthorizationRuleId'), '2021-11-01').primaryConnectionString]"
                            sasPolicyName    = "[parameters('sasPolicyName')]"
                          }]
                        }
                      }]
                    }
                  }
                },
              ]
            }
          }
        }
      }
    }
  })

  defender_export_policy_parameters_json = jsonencode({
    eventHubNamespaceResourceId = {
      type     = "String"
      metadata = { displayName = "Event Hub namespace resource ID" }
    }
    eventHubName = {
      type         = "String"
      metadata     = { displayName = "Event Hub name" }
      defaultValue = "defender-alerts"
    }
    eventHubAuthorizationRuleId = {
      type = "String"
      metadata = {
        displayName       = "Event Hub authorization rule resource ID"
        strongType        = "Microsoft.EventHub/Namespaces/EventHubs/AuthorizationRules"
        assignPermissions = true
      }
    }
    sasPolicyName = {
      type         = "String"
      metadata     = { displayName = "Event Hub SAS policy name" }
      defaultValue = "DefenderExportSend"
    }
    deploymentResourceGroupName = {
      type         = "String"
      metadata     = { displayName = "Target resource group name" }
      defaultValue = "securityhub-defender-export-rg"
    }
    deploymentLocation = {
      type         = "String"
      metadata     = { displayName = "Target location" }
      defaultValue = "eastus"
    }
    automationName = {
      type         = "String"
      metadata     = { displayName = "Defender automation resource name" }
      defaultValue = "securityhub-defender-alerts-export"
    }
  })
}

##################################################
# Defender for Cloud alert export to Event Hub (threats)
##################################################
# DeployIfNotExists at the root management group. In each subscription it
# creates a resource group, then a Microsoft.Security/automations resource that
# exports alerts to the defender-alerts hub. Two nested deployments are needed
# because the automation is resource-group scoped and the group may not exist.
resource "azurerm_policy_definition" "defender_export" {
  count = local.any_threats ? 1 : 0

  name                = local.defender_policy_name
  display_name        = "Deploy SecurityHub Defender for Cloud alerts continuous export"
  policy_type         = "Custom"
  mode                = local.defender_export_policy_mode
  management_group_id = local.mg_id
  policy_rule         = local.defender_export_policy_rule_json
  parameters          = local.defender_export_policy_parameters_json
}

resource "azurerm_management_group_policy_assignment" "defender_export" {
  count = local.any_threats ? 1 : 0

  name                 = local.defender_assignment_name
  management_group_id  = local.mg_id
  policy_definition_id = azurerm_policy_definition.defender_export[0].id
  location             = var.event_hub_location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    eventHubNamespaceResourceId = { value = azurerm_eventhub_namespace.shared.id }
    eventHubName                = { value = local.defender_hub_name }
    eventHubAuthorizationRuleId = { value = local.defender_auth_rule_id }
    sasPolicyName               = { value = local.defender_export_sas_policy }
    deploymentResourceGroupName = { value = local.defender_deployment_rg }
    deploymentLocation          = { value = var.event_hub_location }
    automationName              = { value = local.defender_automation_name }
  })

  depends_on = [azurerm_eventhub_authorization_rule.defender_send]
}
