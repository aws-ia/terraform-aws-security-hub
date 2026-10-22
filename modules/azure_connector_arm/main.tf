data "azurerm_client_config" "current" {}

data "azapi_client_config" "current" {}

locals {
  tenant_id = data.azurerm_client_config.current.tenant_id

  # Management group policy definitions, assignments and most role assignments
  # are scoped to the tenant root management group, whose name is the tenant ID,
  # so they cover every current and future subscription.
  mg_id = "/providers/Microsoft.Management/managementGroups/${local.tenant_id}"

  # ---- Accounts and pipelines ----------------------------------------------
  accounts = {
    for a in var.onboarded_accounts : "${a.aws_account_id}-${a.aws_region}" => a
  }

  any_cspm               = anytrue([for a in var.onboarded_accounts : a.enable_cspm])
  any_inspector          = anytrue([for a in var.onboarded_accounts : a.enable_inspector])
  any_threats            = anytrue([for a in var.onboarded_accounts : a.enable_threats])
  enable_activity_policy = local.any_cspm || local.any_inspector

  # ---- Names ---------------------------------------------------------------
  # The connector finds these resources by name and tag. Keep them unchanged.
  lead_account_id       = var.lead_aws_account_id
  naming_account_suffix = substr(local.lead_account_id, 8, 4)

  event_hub_namespace_name   = coalesce(var.event_hub_namespace_name, "aws-eh-${local.lead_account_id}")
  activity_hub_name          = "activitylog"
  defender_hub_name          = "defender-alerts"
  defender_export_sas_policy = "DefenderExportSend"

  entra_diag_name                  = "EntraIDAuditLogsToEventHub-${local.lead_account_id}"
  activity_policy_name             = "ActivityLogsToEH-${local.naming_account_suffix}"
  acr_policy_name                  = "ACRDiagToEH-${local.naming_account_suffix}"
  vm_identity_policy_name_none     = "inspector-vm-id-none-${local.naming_account_suffix}"
  vm_identity_policy_name_ua       = "inspector-vm-id-ua-${local.naming_account_suffix}"
  vm_identity_assignment_name_none = "sechub-vm-id-none-${local.naming_account_suffix}"
  vm_identity_assignment_name_ua   = "sechub-vm-id-ua-${local.naming_account_suffix}"
  defender_policy_name             = "DeploySecurityHubDefenderAlertsExport-${local.naming_account_suffix}"
  defender_assignment_name         = "sechub-def-alerts-${local.naming_account_suffix}"
  defender_deployment_rg           = "securityhub-defender-export-rg-${local.lead_account_id}"
  defender_automation_name         = "securityhub-defender-alerts-export-${local.naming_account_suffix}"
  vm_runcommand_role_name          = "VM RunCommand Manager-${local.lead_account_id}"
  activity_profile_name            = "setByPolicy-EventHub-Administrative-${local.lead_account_id}"
  acr_profile_name                 = "setByPolicy-EventHub-ContainerRegistryRepositoryEvents-${local.lead_account_id}"

  contributor_role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
  reader_role_definition_id      = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"

  # Lowercase "authorizationrules" matches what the policy deployments write.
  # The value is compared with itself in the policy existence conditions.
  event_hub_auth_rule_id = "${azurerm_eventhub_namespace.shared.id}/authorizationrules/RootManageSharedAccessKey"
  defender_auth_rule_id  = "${azurerm_eventhub_namespace.shared.id}/eventhubs/${local.defender_hub_name}/authorizationrules/${local.defender_export_sas_policy}"

  # ---- Discovery tags ------------------------------------------------------
  # One AWSConfig tag per pair, valued "<hub>:<consumer group>", and one
  # AWSSecurityHub tag per threats-enabled pair, valued with the hub name.
  config_discovery_tags = {
    for k, a in local.accounts :
    "AWSConfig-${k}" => "${local.activity_hub_name}:AWSConfig-${k}"
  }
  securityhub_discovery_tags = {
    for k, a in local.accounts :
    "AWSSecurityHub-${k}" => local.defender_hub_name if a.enable_threats
  }
  acr_discovery_tags = {
    for k, a in local.accounts :
    "AWSConfig-${k}" => "${local.activity_hub_name}:AWSConfig-${k}" if a.enable_inspector
  }

  # ---- Consumer groups -----------------------------------------------------
  activity_consumer_groups = {
    for k, a in local.accounts : k => "AWSConfig-${k}"
  }

  # One group per Inspector-enabled pair on each regional ACR hub.
  acr_consumer_groups = {
    for pair in flatten([
      for tok, loc in local.acr_locations_map : [
        for k, a in local.accounts : {
          key            = "${tok}|${k}"
          token          = tok
          consumer_group = "AWSConfig-${k}"
        } if a.enable_inspector
      ]
    ]) : pair.key => pair
  }

  # ---- Regional ACR namespaces --------------------------------------------
  # Short tokens keep the per-location policy assignment names within Azure's
  # 24-character limit for management group assignments.
  builtin_location_tokens = {
    eastus         = "eus"
    eastus2        = "eus2"
    westus         = "wus"
    westus2        = "wus2"
    westus3        = "wus3"
    centralus      = "cus"
    northcentralus = "ncus"
    southcentralus = "scus"
    canadacentral  = "cac"
    canadaeast     = "cae"
    westeurope     = "weu"
    northeurope    = "neu"
    uksouth        = "uks"
    ukwest         = "ukw"
    eastasia       = "ea"
    southeastasia  = "sea"
    australiaeast  = "aue"
    japaneast      = "jpe"
  }

  acr_locations = local.any_inspector ? var.azure_locations : []

  acr_location_tokens = {
    for loc in local.acr_locations :
    loc => try(var.azure_location_tokens[loc], local.builtin_location_tokens[loc], substr(md5(loc), 0, 6))
  }

  # Grouping with "..." keeps a token collision from failing the expression, so
  # the precondition below can report it.
  acr_token_groups  = { for loc, tok in local.acr_location_tokens : tok => loc... }
  acr_locations_map = { for tok, locs in local.acr_token_groups : tok => locs[0] }

  acr_token_collisions = { for tok, locs in local.acr_token_groups : tok => locs if length(locs) > 1 }

  acr_names_too_long = [
    for tok in keys(local.acr_locations_map) : tok
    if length("${local.acr_policy_name}-${tok}") > 24 || length("${local.event_hub_namespace_name}-${tok}") > 50
  ]
}

##################################################
# Event Hubs
##################################################
resource "azurerm_resource_group" "eventhub" {
  name     = var.event_hub_resource_group_name
  location = var.event_hub_location
  tags     = var.tags

  lifecycle {
    precondition {
      condition     = var.tenant_id == null || lower(coalesce(var.tenant_id, "-")) == lower(local.tenant_id)
      error_message = "The azurerm provider is authenticated to tenant ${local.tenant_id}, but tenant_id is ${coalesce(var.tenant_id, "-")}."
    }

    precondition {
      condition     = lower(data.azapi_client_config.current.tenant_id) == lower(local.tenant_id)
      error_message = "The azapi provider is authenticated to tenant ${data.azapi_client_config.current.tenant_id}, but the azurerm provider is authenticated to ${local.tenant_id}. Configure both providers for the same tenant."
    }

    precondition {
      condition     = length(local.acr_token_collisions) == 0
      error_message = "Several Azure locations map to the same location token: ${jsonencode(local.acr_token_collisions)}. Set distinct values in azure_location_tokens."
    }

    precondition {
      condition     = length(local.acr_names_too_long) == 0
      error_message = "The location tokens ${jsonencode(local.acr_names_too_long)} make a policy assignment name longer than 24 characters or a namespace name longer than 50. Set shorter values in azure_location_tokens or a shorter event_hub_namespace_name."
    }
  }
}

resource "azurerm_eventhub_namespace" "shared" {
  #checkov:skip=CKV_AZURE_228:Zone redundancy is a cost and availability choice that the connector does not depend on.
  name                = local.event_hub_namespace_name
  resource_group_name = azurerm_resource_group.eventhub.name
  location            = var.event_hub_location
  sku                 = "Standard"
  capacity            = 1
  minimum_tls_version = "1.2"

  # Defender for Cloud continuous export authenticates with a SAS connection
  # string, and the policy deployments call listKeys(), so local authentication
  # must stay enabled.
  local_authentication_enabled = true

  tags = merge(var.tags, local.config_discovery_tags, local.securityhub_discovery_tags)
}

resource "azurerm_eventhub" "activity" {
  name              = local.activity_hub_name
  namespace_id      = azurerm_eventhub_namespace.shared.id
  partition_count   = 4
  message_retention = 3
}

resource "azurerm_eventhub_consumer_group" "activity" {
  for_each = local.activity_consumer_groups

  name                = each.value
  namespace_name      = azurerm_eventhub_namespace.shared.name
  eventhub_name       = azurerm_eventhub.activity.name
  resource_group_name = azurerm_resource_group.eventhub.name
}

resource "azurerm_eventhub" "defender" {
  count = local.any_threats ? 1 : 0

  name              = local.defender_hub_name
  namespace_id      = azurerm_eventhub_namespace.shared.id
  partition_count   = 4
  message_retention = 3
}

# The connector reads the defender-alerts hub with the fixed AWSSecurityHub
# consumer group, so there is one group for all accounts.
resource "azurerm_eventhub_consumer_group" "defender" {
  count = local.any_threats ? 1 : 0

  name                = "AWSSecurityHub"
  namespace_name      = azurerm_eventhub_namespace.shared.name
  eventhub_name       = azurerm_eventhub.defender[0].name
  resource_group_name = azurerm_resource_group.eventhub.name
}

# Send-only rule for Defender for Cloud continuous export.
resource "azurerm_eventhub_authorization_rule" "defender_send" {
  count = local.any_threats ? 1 : 0

  name                = local.defender_export_sas_policy
  namespace_name      = azurerm_eventhub_namespace.shared.name
  eventhub_name       = azurerm_eventhub.defender[0].name
  resource_group_name = azurerm_resource_group.eventhub.name

  listen = false
  send   = true
  manage = false
}

# One namespace per ACR location, keyed by location token.
resource "azurerm_eventhub_namespace" "acr" {
  #checkov:skip=CKV_AZURE_228:Zone redundancy is a cost and availability choice that the connector does not depend on.
  for_each = local.acr_locations_map

  name                = "${local.event_hub_namespace_name}-${each.key}"
  resource_group_name = azurerm_resource_group.eventhub.name
  location            = each.value
  sku                 = "Standard"
  capacity            = 1
  minimum_tls_version = "1.2"

  # The ACR policy deployments call listKeys() on the namespace rule.
  local_authentication_enabled = true

  tags = merge(var.tags, local.acr_discovery_tags)
}

resource "azurerm_eventhub" "acr_activity" {
  for_each = local.acr_locations_map

  name              = local.activity_hub_name
  namespace_id      = azurerm_eventhub_namespace.acr[each.key].id
  partition_count   = 4
  message_retention = 3
}

resource "azurerm_eventhub_consumer_group" "acr" {
  for_each = local.acr_consumer_groups

  name                = each.value.consumer_group
  namespace_name      = azurerm_eventhub_namespace.acr[each.value.token].name
  eventhub_name       = azurerm_eventhub.acr_activity[each.value.token].name
  resource_group_name = azurerm_resource_group.eventhub.name
}

##################################################
# Entra ID logs (CSPM)
##################################################
# Tenant-level diagnostic setting. azurerm has no resource for this scope.
# Requires Global Administrator or Security Administrator.
resource "azapi_resource" "entra_diagnostics" {
  count = local.any_cspm ? 1 : 0

  type      = "microsoft.aadiam/diagnosticSettings@2017-04-01"
  name      = local.entra_diag_name
  parent_id = "/"

  # microsoft.aadiam is not in the azapi schema catalogue.
  schema_validation_enabled = false

  # The API returns every log category on read. Manage only the three below.
  ignore_other_items_in_list = ["properties.logs"]
  list_unique_id_property = {
    "properties.logs" = "category"
  }

  body = {
    properties = {
      eventHubAuthorizationRuleId = local.event_hub_auth_rule_id
      eventHubName                = local.activity_hub_name
      logs = [
        { category = "AuditLogs", enabled = true, retentionPolicy = { days = 0, enabled = false } },
        { category = "SignInLogs", enabled = true, retentionPolicy = { days = 0, enabled = false } },
        { category = "NonInteractiveUserSignInLogs", enabled = true, retentionPolicy = { days = 0, enabled = false } },
      ]
    }
  }

  depends_on = [azurerm_eventhub.activity, azurerm_eventhub_consumer_group.activity]
}
