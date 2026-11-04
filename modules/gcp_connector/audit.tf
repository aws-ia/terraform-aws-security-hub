##################################################
# Organization audit configuration
##################################################
# google_organization_iam_audit_config is additive across services but
# authoritative for the service it names: an apply replaces that service's
# whole auditLogConfigs list. To keep the log types and exemptedMembers that
# are already set, this file reads the organization IAM policy during plan and
# declares, for each managed service, the union of the existing log types (with
# their existing exemptedMembers) and the required log types.
#
# Scope: the organization only. Folder and project audit configurations are not
# visible from an organization read.

data "google_organization_iam_policy" "organization" {
  org_id = local.org
}

locals {
  # The audit log types that the connector requires.
  audit_required = merge(
    { "allServices" = ["DATA_WRITE"] },
    local.any_inspector ? { "artifactregistry.googleapis.com" = ["DATA_READ"] } : {},
  )

  audit_existing_configs = try(jsondecode(data.google_organization_iam_policy.organization.policy_data).auditConfigs, [])

  # service => logType => exemptedMembers, as set on the organization now.
  audit_existing = {
    for c in local.audit_existing_configs : c.service => {
      for l in try(c.auditLogConfigs, []) : l.logType => try(l.exemptedMembers, [])
    }
  }

  # The content of each managed service entry after apply.
  audit_managed = {
    for svc, types in local.audit_required : svc => merge(
      { for t in types : t => [] },
      try(local.audit_existing[svc], {}),
    )
  }

  # Exemptions that suppress a required event. For allServices every service
  # entry counts, because GCP adds per-service exemptions to the allServices
  # configuration. For one service, that service's entry and the allServices
  # entry count.
  audit_required_exemptions = sort(distinct(flatten([
    for svc, types in local.audit_required : [
      for c in local.audit_existing_configs : [
        for l in try(c.auditLogConfigs, []) : [
          for m in try(l.exemptedMembers, []) : "${c.service} ${l.logType} ${m}"
        ] if contains(types, l.logType)
      ] if svc == "allServices" || c.service == svc || c.service == "allServices"
    ]
  ])))
}

# allServices DATA_WRITE feeds the AWS Config lifecycle sink. Audit volume
# starts only after the routes and grants exist.
resource "google_organization_iam_audit_config" "all_services_write" {
  org_id  = local.org
  service = "allServices"

  dynamic "audit_log_config" {
    for_each = local.audit_managed["allServices"]
    content {
      log_type         = audit_log_config.key
      exempted_members = audit_log_config.value
    }
  }

  depends_on = [
    terraform_data.preflight,
    google_logging_organization_sink.lifecycle,
    google_pubsub_topic_iam_member.lifecycle_writer,
    google_cloud_asset_organization_feed.cai,
    google_organization_iam_member.connector_read,
  ]
}

# Artifact Registry DATA_READ: image-pull events for Amazon Inspector.
resource "google_organization_iam_audit_config" "artifactregistry_read" {
  count = local.any_inspector ? 1 : 0

  org_id  = local.org
  service = "artifactregistry.googleapis.com"

  dynamic "audit_log_config" {
    for_each = local.audit_managed["artifactregistry.googleapis.com"]
    content {
      log_type         = audit_log_config.key
      exempted_members = audit_log_config.value
    }
  }

  depends_on = [
    terraform_data.preflight,
    google_logging_organization_sink.inspector_pull,
    google_pubsub_topic_iam_member.inspector_pull_writer,
    google_organization_iam_member.inspector_function_source,
  ]
}
