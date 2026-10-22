##################################################
# Connector service principal
##################################################
# Reader at the tenant root scope "/". Reader at the root management group does
# not cover role assignments created at "/", which the connector reads.
# azurerm_role_assignment cannot manage an assignment at "/"
# (hashicorp/terraform-provider-azurerm#24536), so this uses azapi.
resource "azapi_resource" "sp_reader" {
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  parent_id = "/"
  name      = uuidv5("url", "https://securityhub.aws/azure/${local.tenant_id}/reader/${var.service_principal_object_id}")

  body = {
    properties = {
      roleDefinitionId = local.reader_role_definition_id
      principalId      = var.service_principal_object_id
      principalType    = "ServicePrincipal"
    }
  }

  # Azure does not allow changing the principal or role of an assignment. The
  # external value also covers a plan where the principal ID is not yet known.
  replace_triggers_refs            = ["properties.principalId", "properties.roleDefinitionId"]
  replace_triggers_external_values = [var.service_principal_object_id]

  # A service principal created in the same apply may not have replicated yet.
  retry = {
    error_message_regex = ["PrincipalNotFound"]
  }

  timeouts {
    create = "5m"
  }
}

# Inspector scans resources across the tenant. Created only when an account
# enables Inspector.
resource "azurerm_role_assignment" "sp_contributor" {
  count = local.any_inspector ? 1 : 0

  scope                            = local.mg_id
  role_definition_name             = "Contributor"
  principal_id                     = var.service_principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# At the tenant root management group, so one assignment covers the shared
# namespace and every regional namespace. It also lets the connector receive
# from Event Hub namespaces this module does not manage. With Inspector enabled
# the Contributor assignment above already includes listKeys on every
# namespace; for a CSPM- or threats-only deployment this assignment is the
# broader access.
resource "azurerm_role_assignment" "sp_eventhubs_data_receiver" {
  scope                            = local.mg_id
  role_definition_name             = "Azure Event Hubs Data Receiver"
  principal_id                     = var.service_principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Inspector runs SSM through VM Run Command. No built-in role grants exactly
# these actions.
resource "azurerm_role_definition" "vm_runcommand" {
  count = local.any_inspector ? 1 : 0

  name        = local.vm_runcommand_role_name
  scope       = local.mg_id
  description = "VM RunCommand operations for Inspector (AWS ${local.lead_account_id})"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/runCommands/write",
      "Microsoft.Compute/virtualMachines/runCommands/read",
      "Microsoft.Compute/virtualMachines/runCommands/delete",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
    ]
    not_actions = []
  }

  assignable_scopes = [local.mg_id]
}

resource "azurerm_role_assignment" "sp_vm_runcommand" {
  count = local.any_inspector ? 1 : 0

  scope                            = local.mg_id
  role_definition_id               = azurerm_role_definition.vm_runcommand[0].role_definition_resource_id
  principal_id                     = var.service_principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

##################################################
# Policy assignment managed identities
##################################################
# DeployIfNotExists and modify policies run their deployments as the
# assignment's managed identity. Each identity gets Contributor at the root
# management group. The activity log and ACR identities also get Event Hubs Data
# Owner on their namespace, for the listKeys() call in their deployments.
#
# Namespace-scoped grants use role_definition_name: Azure returns a
# subscription-qualified role definition ID for them, which would never match a
# tenant-level ID in configuration and would force a replacement on every apply.
locals {
  policy_identities = merge(
    local.enable_activity_policy ? {
      activity = azurerm_management_group_policy_assignment.activity_log[0].identity[0].principal_id
    } : {},
    { for tok, a in azurerm_management_group_policy_assignment.acr_diagnostics : "acr-${tok}" => a.identity[0].principal_id },
    local.any_inspector ? {
      vm_none = azurerm_management_group_policy_assignment.vm_identity_none[0].identity[0].principal_id
      vm_ua   = azurerm_management_group_policy_assignment.vm_identity_ua[0].identity[0].principal_id
    } : {},
    local.any_threats ? {
      defender = azurerm_management_group_policy_assignment.defender_export[0].identity[0].principal_id
    } : {},
  )

  # Keys must be known at plan time, so they are built from configuration, not
  # from the assignments.
  policy_identity_keys = concat(
    local.enable_activity_policy ? ["activity"] : [],
    [for tok in keys(local.acr_locations_map) : "acr-${tok}"],
    local.any_inspector ? ["vm_none", "vm_ua"] : [],
    local.any_threats ? ["defender"] : [],
  )

  policy_identity_namespaces = merge(
    local.enable_activity_policy ? { activity = azurerm_eventhub_namespace.shared.id } : {},
    { for tok, ns in azurerm_eventhub_namespace.acr : "acr-${tok}" => ns.id },
  )

  policy_identity_namespace_keys = concat(
    local.enable_activity_policy ? ["activity"] : [],
    [for tok in keys(local.acr_locations_map) : "acr-${tok}"],
  )
}

resource "azurerm_role_assignment" "policy_contributor" {
  for_each = toset(local.policy_identity_keys)

  scope                            = local.mg_id
  role_definition_id               = local.contributor_role_definition_id
  principal_id                     = local.policy_identities[each.key]
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "policy_eventhubs_data_owner" {
  for_each = toset(local.policy_identity_namespace_keys)

  scope                            = local.policy_identity_namespaces[each.key]
  role_definition_name             = "Azure Event Hubs Data Owner"
  principal_id                     = local.policy_identities[each.key]
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
