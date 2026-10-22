locals {
  vm_identity_none_policy_mode = "Indexed"

  vm_identity_none_policy_rule_json = jsonencode({
    "if" = {
      allOf = [
        { field = "type", equals = "Microsoft.Compute/virtualMachines" },
        {
          anyOf = [
            { field = "identity.type", exists = "false" },
            { field = "identity.type", equals = "None" },
          ]
        },
      ]
    }
    "then" = {
      effect = "modify"
      details = {
        roleDefinitionIds = [local.contributor_role_definition_id]
        operations = [
          { operation = "addOrReplace", field = "identity.type", value = "SystemAssigned" },
        ]
      }
    }
  })

  vm_identity_ua_policy_mode = "Indexed"

  vm_identity_ua_policy_rule_json = jsonencode({
    "if" = {
      allOf = [
        { field = "type", equals = "Microsoft.Compute/virtualMachines" },
        { field = "identity.type", equals = "UserAssigned" },
      ]
    }
    "then" = {
      effect = "modify"
      details = {
        roleDefinitionIds = [local.contributor_role_definition_id]
        operations = [
          {
            operation = "addOrReplace"
            field     = "identity.type"
            # Same literal as Microsoft's built-in 497dff13 (no space); Azure
            # accepts and canonicalizes it.
            value = "[concat(field('identity.type'), ',SystemAssigned')]"
          },
        ]
      }
    }
  })
}

##################################################
# System-assigned identity on every VM (Inspector)
##################################################
# Inspector scans VMs through a system-assigned managed identity. Two modify
# policies add one without redeploying the VM:
#   none: identity.type absent or "None" -> "SystemAssigned"
#   ua:   identity.type "UserAssigned"   -> "UserAssigned,SystemAssigned"
# A VM that already has a system-assigned identity matches neither.
resource "azurerm_policy_definition" "vm_identity_none" {
  count = local.any_inspector ? 1 : 0

  name                = local.vm_identity_policy_name_none
  display_name        = "Add SystemAssigned identity to VMs with no identity (AWS ${local.lead_account_id})"
  policy_type         = "Custom"
  mode                = local.vm_identity_none_policy_mode
  management_group_id = local.mg_id
  policy_rule         = local.vm_identity_none_policy_rule_json
}

resource "azurerm_management_group_policy_assignment" "vm_identity_none" {
  count = local.any_inspector ? 1 : 0

  name                 = local.vm_identity_assignment_name_none
  management_group_id  = local.mg_id
  policy_definition_id = azurerm_policy_definition.vm_identity_none[0].id
  location             = var.event_hub_location

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_policy_definition" "vm_identity_ua" {
  count = local.any_inspector ? 1 : 0

  name                = local.vm_identity_policy_name_ua
  display_name        = "Add SystemAssigned identity to VMs with UserAssigned (AWS ${local.lead_account_id})"
  policy_type         = "Custom"
  mode                = local.vm_identity_ua_policy_mode
  management_group_id = local.mg_id
  policy_rule         = local.vm_identity_ua_policy_rule_json
}

resource "azurerm_management_group_policy_assignment" "vm_identity_ua" {
  count = local.any_inspector ? 1 : 0

  name                 = local.vm_identity_assignment_name_ua
  management_group_id  = local.mg_id
  policy_definition_id = azurerm_policy_definition.vm_identity_ua[0].id
  location             = var.event_hub_location

  identity {
    type = "SystemAssigned"
  }
}
