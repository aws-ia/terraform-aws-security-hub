mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "aaaaaaaa-0000-0000-0000-000000000001"
    }
  }

  mock_data "azurerm_subscriptions" {
    defaults = {
      subscriptions = [
        {
          subscription_id = "aaaaaaaa-0000-0000-0000-000000000001"
          tenant_id       = "11111111-1111-1111-1111-111111111111"
          state           = "Enabled"
        },
        {
          subscription_id = "AAAAAAAA-0000-0000-0000-000000000002"
          tenant_id       = "11111111-1111-1111-1111-111111111111"
          state           = "Enabled"
        },
        {
          subscription_id = "aaaaaaaa-0000-0000-0000-000000000003"
          tenant_id       = "11111111-1111-1111-1111-111111111111"
          state           = "Disabled"
        },
        {
          subscription_id = "bbbbbbbb-0000-0000-0000-000000000004"
          tenant_id       = "99999999-9999-9999-9999-999999999999"
          state           = "Enabled"
        },
      ]
    }
  }
}

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  lead_aws_account_id         = "123456789012"
  service_principal_object_id = "33333333-3333-3333-3333-333333333333"
  application_client_id       = "55555555-5555-5555-5555-555555555555"
  azure_locations             = ["eastus", "westeurope"]
  onboarded_accounts = [
    {
      aws_account_id = "123456789012"
      aws_region     = "us-east-1"
      issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
    },
    {
      aws_account_id   = "210987654321"
      aws_region       = "eu-west-1"
      issuer_url       = "https://ffffffff-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
      enable_inspector = false
      enable_threats   = false
    },
  ]
}

run "all_pipelines" {
  command = plan

  assert {
    condition     = azurerm_eventhub_namespace.shared.name == "aws-eh-123456789012"
    error_message = "The shared namespace must be named aws-eh-<lead account>."
  }

  assert {
    condition = azurerm_eventhub_namespace.shared.tags == tomap({
      "AWSConfig-123456789012-us-east-1"      = "activitylog:AWSConfig-123456789012-us-east-1"
      "AWSConfig-210987654321-eu-west-1"      = "activitylog:AWSConfig-210987654321-eu-west-1"
      "AWSSecurityHub-123456789012-us-east-1" = "defender-alerts"
    })
    error_message = "Discovery tags must name the hub and consumer group for each pair, and the defender hub for threats-enabled pairs."
  }

  assert {
    condition     = toset(keys(azurerm_eventhub_namespace.acr)) == toset(["eus", "weu"])
    error_message = "Each ACR location needs a regional namespace keyed by its token."
  }

  assert {
    condition     = azurerm_role_assignment.sp_contributor[0].scope == "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111" && azurerm_role_assignment.sp_contributor[0].role_definition_name == "Contributor"
    error_message = "With Inspector enabled, the connector needs Contributor at the tenant root management group."
  }

  assert {
    condition     = azurerm_eventhub_namespace.acr["weu"].tags == tomap({ "AWSConfig-123456789012-us-east-1" = "activitylog:AWSConfig-123456789012-us-east-1" })
    error_message = "Regional namespaces carry discovery tags only for Inspector-enabled pairs."
  }

  assert {
    condition     = length(azurerm_eventhub_consumer_group.activity) == 2 && length(azurerm_eventhub_consumer_group.acr) == 2
    error_message = "One activitylog consumer group per pair, and one per location for each Inspector-enabled pair."
  }

  assert {
    condition     = azurerm_eventhub_consumer_group.defender[0].name == "AWSSecurityHub"
    error_message = "The defender hub uses the fixed AWSSecurityHub consumer group."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.acr_diagnostics["eus"].name == "ACRDiagToEH-9012-eus"
    error_message = "ACR assignment names must be ACRDiagToEH-<last 4 digits>-<token>."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.activity_log[0].management_group_id == "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111"
    error_message = "Policies must be assigned at the tenant root management group."
  }

  assert {
    condition     = azapi_resource.sp_reader.parent_id == "/"
    error_message = "The connector Reader role must be assigned at the tenant root scope."
  }

  assert {
    condition     = azurerm_role_assignment.sp_eventhubs_data_receiver.scope == "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111"
    error_message = "The connector Event Hubs Data Receiver role must be assigned once, at the tenant root management group."
  }

  assert {
    condition = (
      jsondecode(local.defender_export_policy_rule_json).then.details.deployment.properties.expressionEvaluationOptions.scope == "outer" &&
      jsondecode(local.defender_export_policy_rule_json).then.details.deployment.properties.template.resources[1].properties.expressionEvaluationOptions.scope == "inner"
    )
    error_message = "The Defender export deployment must use the outer evaluation scope and its nested resource group deployment the inner scope."
  }

  assert {
    condition     = length(azurerm_role_assignment.policy_contributor) == 6 && length(azurerm_role_assignment.policy_eventhubs_data_owner) == 3
    error_message = "Every policy identity needs Contributor; activity log and ACR identities also need Event Hubs Data Owner."
  }

  assert {
    condition     = output.remediation_subscription_ids == tolist(["aaaaaaaa-0000-0000-0000-000000000001", "aaaaaaaa-0000-0000-0000-000000000002"])
    error_message = "Only enabled subscriptions in the provider's tenant are remediated, with IDs in lower case."
  }

  assert {
    condition     = length(azurerm_management_group_policy_remediation.existing_resources) == 6
    error_message = "Each of the six assignments needs one remediation task."
  }

  assert {
    condition = alltrue([
      for r in azurerm_management_group_policy_remediation.existing_resources :
      r.management_group_id == "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111"
    ])
    error_message = "Remediation tasks must be created at the tenant root management group."
  }

  assert {
    condition     = azurerm_management_group_policy_remediation.existing_resources["acr-weu"].name == "acrdiagtoeh-9012-weu-remediation"
    error_message = "Remediation task names must be the lower-case assignment name with a -remediation suffix."
  }

  assert {
    condition = alltrue([
      for r in azurerm_management_group_policy_remediation.existing_resources : r.resource_count == 500
    ])
    error_message = "Remediation tasks must default to Azure's 500-resource count."
  }

  assert {
    condition     = toset(keys(azapi_resource_action.compliance_scan)) == toset(["aaaaaaaa-0000-0000-0000-000000000001", "aaaaaaaa-0000-0000-0000-000000000002"])
    error_message = "Each enabled subscription in the tenant must be scanned for compliance before remediation."
  }

  assert {
    condition     = azapi_resource_action.compliance_scan["aaaaaaaa-0000-0000-0000-000000000001"].resource_id == "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/providers/Microsoft.PolicyInsights/policyStates/latest" && azapi_resource_action.compliance_scan["aaaaaaaa-0000-0000-0000-000000000001"].action == "triggerEvaluation"
    error_message = "The compliance scan must call triggerEvaluation on the subscription's latest policy states."
  }

  assert {
    condition     = length(azapi_resource_action.register_provider) == 8
    error_message = "Four resource providers must be registered in each of two subscriptions."
  }

  assert {
    condition     = azapi_resource_action.register_policy_insights_mg[0].resource_id == "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111" && azapi_resource_action.register_policy_insights_mg[0].action == "providers/Microsoft.PolicyInsights/register"
    error_message = "Microsoft.PolicyInsights must be registered on the tenant root management group for the remediation tasks."
  }

  assert {
    condition     = length(azapi_resource.entra_diagnostics) == 1
    error_message = "CSPM needs the Entra ID diagnostic setting."
  }
}

run "tags_applied" {
  command = plan

  variables {
    tags = { Environment = "test" }
  }

  assert {
    condition     = azurerm_resource_group.eventhub.tags == tomap({ Environment = "test" })
    error_message = "var.tags must be applied to the resource group."
  }

  assert {
    condition     = azurerm_eventhub_namespace.acr["eus"].tags["Environment"] == "test" && azurerm_eventhub_namespace.shared.tags["Environment"] == "test"
    error_message = "var.tags must be merged onto every namespace."
  }
}

run "cspm_only" {
  command = plan

  variables {
    azure_locations              = []
    remediation_subscription_ids = ["aaaaaaaa-0000-0000-0000-000000000001"]
    remediation_resource_count   = 50000
    register_resource_providers  = false
    onboarded_accounts = [
      {
        aws_account_id   = "123456789012"
        aws_region       = "us-east-1"
        issuer_url       = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
        enable_inspector = false
        enable_threats   = false
      },
    ]
  }

  assert {
    condition = (
      length(azurerm_eventhub.defender) == 0 &&
      length(azurerm_eventhub_namespace.acr) == 0 &&
      length(azurerm_role_definition.vm_runcommand) == 0
    )
    error_message = "CSPM alone must not create threat or Inspector resources."
  }

  assert {
    condition     = length(azurerm_role_assignment.sp_contributor) == 0
    error_message = "CSPM alone must not grant the connector Contributor."
  }

  assert {
    condition     = keys(azurerm_management_group_policy_remediation.existing_resources) == ["activity"] && keys(azapi_resource_action.compliance_scan) == ["aaaaaaaa-0000-0000-0000-000000000001"]
    error_message = "CSPM alone remediates only the activity log assignment, and scans only the listed subscriptions."
  }

  assert {
    condition     = azurerm_management_group_policy_remediation.existing_resources["activity"].resource_count == 50000
    error_message = "remediation_resource_count must set the remediation tasks' resource count."
  }

  assert {
    condition     = length(azapi_resource_action.register_provider) == 0 && length(azapi_resource_action.register_policy_insights_mg) == 0
    error_message = "register_resource_providers = false must skip registration, including on the management group."
  }
}

run "no_remediation" {
  command = plan

  variables {
    create_policy_remediations  = false
    register_resource_providers = false
  }

  assert {
    condition     = length(azurerm_management_group_policy_remediation.existing_resources) == 0 && length(azapi_resource_action.compliance_scan) == 0
    error_message = "create_policy_remediations = false must skip remediation tasks and compliance scans."
  }
}

run "rejects_tenant_mismatch" {
  command = plan

  variables {
    tenant_id = "99999999-9999-9999-9999-999999999999"
  }

  expect_failures = [azurerm_resource_group.eventhub]
}

run "rejects_azapi_tenant_mismatch" {
  command = plan

  override_data {
    target = data.azapi_client_config.current
    values = {
      tenant_id = "99999999-9999-9999-9999-999999999999"
    }
  }

  expect_failures = [azurerm_resource_group.eventhub]
}

run "rejects_token_collision" {
  command = plan

  variables {
    azure_location_tokens = {
      eastus     = "x"
      westeurope = "x"
    }
  }

  expect_failures = [azurerm_resource_group.eventhub]
}

run "rejects_inspector_without_locations" {
  command = plan

  variables {
    azure_locations = []
  }

  expect_failures = [var.azure_locations]
}

run "rejects_non_canonical_location" {
  command = plan

  variables {
    azure_locations = ["East US"]
  }

  expect_failures = [var.azure_locations]
}

run "policy_content" {
  # apply, against the mocked providers only, so the overridden namespace IDs are
  # known when the assignment parameters are checked.
  command = apply

  variables {
    # The fixtures render deployment.location for eastus.
    event_hub_location          = "eastus"
    create_policy_remediations  = false
    register_resource_providers = false
  }

  override_resource {
    target = azurerm_policy_definition.activity_log
    values = { id = "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyDefinitions/activity" }
  }

  override_resource {
    target = azurerm_policy_definition.acr_diagnostics
    values = { id = "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyDefinitions/acr" }
  }

  override_resource {
    target = azurerm_policy_definition.vm_identity_none
    values = { id = "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyDefinitions/vm-none" }
  }

  override_resource {
    target = azurerm_policy_definition.vm_identity_ua
    values = { id = "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyDefinitions/vm-ua" }
  }

  override_resource {
    target = azurerm_policy_definition.defender_export
    values = { id = "/providers/Microsoft.Management/managementGroups/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/policyDefinitions/defender" }
  }

  override_resource {
    target = azurerm_eventhub_namespace.shared
    values = {
      id = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012"
    }
  }

  override_resource {
    target = azurerm_eventhub_namespace.acr
    values = {
      id = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012-acr"
    }
  }

  # The policy rules and parameter definitions must match the fixtures exactly.
  assert {
    condition     = jsondecode(local.activity_log_policy_rule_json) == jsondecode(file("${path.module}/tests/fixtures/activity_log_policy_rule.json"))
    error_message = "The activity log policy rule does not match tests/fixtures/activity_log_policy_rule.json."
  }

  assert {
    condition     = jsondecode(local.activity_log_policy_parameters_json) == jsondecode(file("${path.module}/tests/fixtures/activity_log_policy_parameters.json"))
    error_message = "The activity log policy parameters do not match tests/fixtures/activity_log_policy_parameters.json."
  }

  assert {
    condition     = jsondecode(local.acr_diagnostics_policy_rule_json) == jsondecode(file("${path.module}/tests/fixtures/acr_diagnostics_policy_rule.json"))
    error_message = "The ACR diagnostics policy rule does not match tests/fixtures/acr_diagnostics_policy_rule.json."
  }

  assert {
    condition     = jsondecode(local.acr_diagnostics_policy_parameters_json) == jsondecode(file("${path.module}/tests/fixtures/acr_diagnostics_policy_parameters.json"))
    error_message = "The ACR diagnostics policy parameters do not match tests/fixtures/acr_diagnostics_policy_parameters.json."
  }

  assert {
    condition     = jsondecode(local.vm_identity_none_policy_rule_json) == jsondecode(file("${path.module}/tests/fixtures/vm_identity_none_policy_rule.json"))
    error_message = "The VM identity (none) policy rule does not match tests/fixtures/vm_identity_none_policy_rule.json."
  }

  assert {
    condition     = jsondecode(local.vm_identity_ua_policy_rule_json) == jsondecode(file("${path.module}/tests/fixtures/vm_identity_ua_policy_rule.json"))
    error_message = "The VM identity (user-assigned) policy rule does not match tests/fixtures/vm_identity_ua_policy_rule.json."
  }

  assert {
    condition     = jsondecode(local.defender_export_policy_rule_json) == jsondecode(file("${path.module}/tests/fixtures/defender_export_policy_rule.json"))
    error_message = "The Defender export policy rule does not match tests/fixtures/defender_export_policy_rule.json."
  }

  assert {
    condition     = jsondecode(local.defender_export_policy_parameters_json) == jsondecode(file("${path.module}/tests/fixtures/defender_export_policy_parameters.json"))
    error_message = "The Defender export policy parameters do not match tests/fixtures/defender_export_policy_parameters.json."
  }

  # Assignment parameters.
  assert {
    condition = jsondecode(azurerm_management_group_policy_assignment.activity_log[0].parameters) == {
      eventHubAuthorizationRuleId = { value = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012/authorizationrules/RootManageSharedAccessKey" }
      eventHubName                = { value = "activitylog" }
      profileName                 = { value = "setByPolicy-EventHub-Administrative-123456789012" }
    }
    error_message = "The activity log assignment must target the shared namespace's root rule, the activitylog hub and the account-suffixed profile name."
  }

  assert {
    condition = jsondecode(azurerm_management_group_policy_assignment.acr_diagnostics["eus"].parameters) == {
      eventHubAuthorizationRuleId = { value = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012-acr/authorizationrules/RootManageSharedAccessKey" }
      eventHubName                = { value = "activitylog" }
      eventHubLocation            = { value = "eastus" }
      profileName                 = { value = "setByPolicy-EventHub-ContainerRegistryRepositoryEvents-123456789012" }
    }
    error_message = "Each ACR assignment must target its regional namespace's root rule, its own location and the account-suffixed profile name."
  }

  assert {
    condition = jsondecode(azurerm_management_group_policy_assignment.defender_export[0].parameters) == {
      eventHubNamespaceResourceId = { value = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012" }
      eventHubName                = { value = "defender-alerts" }
      eventHubAuthorizationRuleId = { value = "/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/aws-eventhub-rg/providers/Microsoft.EventHub/namespaces/aws-eh-123456789012/eventhubs/defender-alerts/authorizationrules/DefenderExportSend" }
      sasPolicyName               = { value = "DefenderExportSend" }
      deploymentResourceGroupName = { value = "securityhub-defender-export-rg-123456789012" }
      deploymentLocation          = { value = "eastus" }
      automationName              = { value = "securityhub-defender-alerts-export-9012" }
    }
    error_message = "The Defender assignment must use the hub-scoped send-only rule and the account-suffixed resource group and automation names."
  }

  assert {
    condition = azurerm_role_definition.vm_runcommand[0].permissions[0].actions == tolist([
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/runCommands/write",
      "Microsoft.Compute/virtualMachines/runCommands/read",
      "Microsoft.Compute/virtualMachines/runCommands/delete",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
    ])
    error_message = "The VM Run Command role must grant exactly the VM read and Run Command actions Inspector uses."
  }
}
