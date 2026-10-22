##################################################
# Resource provider registration and policy remediation
##################################################
# DeployIfNotExists and modify policies only act on resources created or
# updated after the assignment. A remediation task fixes the resources that
# already exist. The module scans each subscription for compliance, then
# creates one remediation task per policy assignment at the tenant root
# management group.
data "azurerm_subscriptions" "available" {
  count = var.remediation_subscription_ids == null && (var.register_resource_providers || var.create_policy_remediations) ? 1 : 0
}

locals {
  remediation_subscription_ids = var.remediation_subscription_ids != null ? toset([for id in var.remediation_subscription_ids : lower(id)]) : toset([
    for s in try(data.azurerm_subscriptions.available[0].subscriptions, []) : lower(s.subscription_id)
    if lower(s.tenant_id) == lower(local.tenant_id) && s.state == "Enabled"
  ])

  resource_providers = concat(
    ["Microsoft.Insights", "Microsoft.EventHub", "Microsoft.PolicyInsights"],
    local.any_threats ? ["Microsoft.Security"] : [],
  )

  provider_registrations = var.register_resource_providers ? {
    for pair in setproduct(local.remediation_subscription_ids, local.resource_providers) :
    "${pair[0]}/${pair[1]}" => { subscription_id = pair[0], namespace = pair[1] }
  } : {}

  # Policy assignments to remediate, keyed like local.policy_identity_keys.
  policy_assignment_ids = merge(
    local.enable_activity_policy ? { activity = azurerm_management_group_policy_assignment.activity_log[0].id } : {},
    { for tok, a in azurerm_management_group_policy_assignment.acr_diagnostics : "acr-${tok}" => a.id },
    local.any_inspector ? {
      vm_none = azurerm_management_group_policy_assignment.vm_identity_none[0].id
      vm_ua   = azurerm_management_group_policy_assignment.vm_identity_ua[0].id
    } : {},
    local.any_threats ? { defender = azurerm_management_group_policy_assignment.defender_export[0].id } : {},
  )

  policy_assignment_names = merge(
    local.enable_activity_policy ? { activity = local.activity_policy_name } : {},
    { for tok in keys(local.acr_locations_map) : "acr-${tok}" => "${local.acr_policy_name}-${tok}" },
    local.any_inspector ? {
      vm_none = local.vm_identity_assignment_name_none
      vm_ua   = local.vm_identity_assignment_name_ua
    } : {},
    local.any_threats ? { defender = local.defender_assignment_name } : {},
  )

  # A digest of each policy's rule and assignment parameters, built from
  # configuration rather than from values Azure returns (Azure reformats policy
  # JSON on read). When it changes, the remediation tasks are replaced so
  # existing resources are evaluated against the new policy.
  policy_generations = merge(
    local.enable_activity_policy ? {
      activity = sha256(jsonencode([
        local.activity_log_policy_rule_json, local.activity_log_policy_parameters_json,
        var.event_hub_location, local.event_hub_auth_rule_id, local.activity_profile_name,
      ]))
    } : {},
    {
      for tok, loc in local.acr_locations_map : "acr-${tok}" => sha256(jsonencode([
        local.acr_diagnostics_policy_rule_json, local.acr_diagnostics_policy_parameters_json,
        loc, azurerm_eventhub_namespace.acr[tok].id, local.acr_profile_name,
      ]))
    },
    local.any_inspector ? {
      vm_none = sha256(jsonencode([local.vm_identity_none_policy_rule_json, var.event_hub_location]))
      vm_ua   = sha256(jsonencode([local.vm_identity_ua_policy_rule_json, var.event_hub_location]))
    } : {},
    local.any_threats ? {
      defender = sha256(jsonencode([
        local.defender_export_policy_rule_json, local.defender_export_policy_parameters_json,
        var.event_hub_location, local.defender_auth_rule_id,
        local.defender_deployment_rg, local.defender_automation_name,
      ]))
    } : {},
  )

  remediation_keys = var.create_policy_remediations ? toset(local.policy_identity_keys) : toset([])

  compliance_scans = var.create_policy_remediations ? local.remediation_subscription_ids : toset([])

  # Sorted so the order Azure lists subscriptions in does not cause a change.
  remediation_subscriptions_sorted = sort(tolist(local.remediation_subscription_ids))
}

resource "azapi_resource_action" "register_provider" {
  for_each = local.provider_registrations

  type        = "Microsoft.Resources/providers@2021-04-01"
  resource_id = "/subscriptions/${each.value.subscription_id}/providers/${each.value.namespace}"
  action      = "register"
  method      = "POST"
}

# Remediation tasks at the management group need Microsoft.PolicyInsights
# registered on the management group itself; Azure rejects some of them with
# ManagementGroupNotRegistered otherwise. Subscription registration does not
# cover the management group.
resource "azapi_resource_action" "register_policy_insights_mg" {
  count = var.register_resource_providers && var.create_policy_remediations ? 1 : 0

  type        = "Microsoft.Management/managementGroups@2021-04-01"
  resource_id = local.mg_id
  action      = "providers/Microsoft.PolicyInsights/register"
  method      = "POST"
}

# Changes when any policy or the subscription list changes, so every
# subscription is scanned again before the remediation tasks are replaced.
resource "terraform_data" "compliance_scan_generation" {
  count = var.create_policy_remediations ? 1 : 0

  input = {
    policies      = local.policy_generations
    subscriptions = local.remediation_subscriptions_sorted
  }
}

# A management group remediation task only fixes resources that Azure has
# already evaluated as non-compliant, and a new assignment has no compliance
# results yet. An on-demand scan of each subscription produces them. Terraform
# waits for each scan to finish.
resource "azapi_resource_action" "compliance_scan" {
  for_each = local.compliance_scans

  type        = "Microsoft.PolicyInsights/policyStates@2019-10-01"
  resource_id = "/subscriptions/${each.value}/providers/Microsoft.PolicyInsights/policyStates/latest"
  action      = "triggerEvaluation"
  method      = "POST"

  timeouts {
    create = var.compliance_scan_timeout
  }

  lifecycle {
    replace_triggered_by = [terraform_data.compliance_scan_generation]
  }

  depends_on = [
    azapi_resource_action.register_provider,
    azurerm_management_group_policy_assignment.activity_log,
    azurerm_management_group_policy_assignment.acr_diagnostics,
    azurerm_management_group_policy_assignment.vm_identity_none,
    azurerm_management_group_policy_assignment.vm_identity_ua,
    azurerm_management_group_policy_assignment.defender_export,
  ]
}

# Changes when the policy or the subscription list changes. A new
# subscription replaces the tasks so its existing resources are fixed too.
resource "terraform_data" "policy_generation" {
  for_each = local.remediation_keys

  input = {
    policy        = local.policy_generations[each.key]
    subscriptions = local.remediation_subscriptions_sorted
  }
}

# One task per policy assignment at the tenant root management group. Each
# covers every subscription in the tenant.
resource "azurerm_management_group_policy_remediation" "existing_resources" {
  for_each = local.remediation_keys

  # Remediation names must be lower case.
  name                 = lower("${local.policy_assignment_names[each.key]}-remediation")
  management_group_id  = local.mg_id
  policy_assignment_id = local.policy_assignment_ids[each.key]
  resource_count       = var.remediation_resource_count

  lifecycle {
    replace_triggered_by = [terraform_data.policy_generation[each.key]]
  }

  # The managed identities need their roles before the deployments run, and
  # the compliance results must exist before the task looks for resources.
  depends_on = [
    azapi_resource_action.register_provider,
    azapi_resource_action.register_policy_insights_mg,
    azapi_resource_action.compliance_scan,
    azurerm_role_assignment.policy_contributor,
    azurerm_role_assignment.policy_eventhubs_data_owner,
  ]
}
