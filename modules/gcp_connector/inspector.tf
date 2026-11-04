##################################################
# Amazon Inspector
##################################################
# Per-account resources follow the account rollup (enable_inspector,
# enable_inspector_vm). The two custom roles, the service agents, VM Manager in
# the target projects and the Artifact Registry read audit log belong to the
# organization or to a project, and are created once when any account needs
# them.

locals {
  inspector_accounts = {
    for id, n in local.account_names : id => n if local.account_flags[id].enable_inspector
  }

  inspector_vm_accounts = {
    for id, n in local.account_names : id => n if local.account_flags[id].enable_inspector_vm
  }

  inspector_subscriptions = {
    for k, s in local.subscriptions : k => s if s.enable_inspector
  }

  vm_targets = local.any_inspector_vm ? toset(var.target_project_ids) : toset([])

  inspector_function_source_role = "inspectorFunctionSourceReader"
  inspector_vm_deployer_role     = "OSPolicySSMDeployer"

  inspector_function_source_permissions = ["cloudfunctions.functions.sourceCodeGet"]

  inspector_vm_deployer_permissions = [
    "cloudasset.assets.searchAllResources",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.projects.get",
    "compute.regions.get",
    "compute.zoneOperations.get",
    "iam.serviceAccounts.actAs",
    "osconfig.inventories.get",
    "osconfig.inventories.list",
    "osconfig.osPolicyAssignments.create",
    "osconfig.osPolicyAssignments.update",
    "osconfig.osPolicyAssignments.get",
    "osconfig.osPolicyAssignments.list",
    "osconfig.osPolicyAssignments.delete",
    "osconfig.osPolicyAssignmentReports.list",
    "osconfig.osPolicyAssignmentReports.get",
    "osconfig.policyOrchestrators.create",
    "osconfig.policyOrchestrators.update",
    "osconfig.policyOrchestrators.get",
    "osconfig.policyOrchestrators.list",
    "osconfig.policyOrchestrators.delete",
    "osconfig.operations.get",
    "osconfig.operations.list",
    "resourcemanager.projects.get",
    "serviceusage.services.get",
    "serviceusage.services.list",
  ]

  # Container image pulls from Artifact Registry, without the pulls that Google
  # scanning agents and the connector service accounts make.
  inspector_pull_filter = trimspace(<<-EOT
    logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="artifactregistry.googleapis.com" AND protoPayload.methodName="Docker-GetManifest" AND (protoPayload.authenticationInfo.principalEmail:* OR protoPayload.authenticationInfo.principalSubject:*) AND NOT (protoPayload.authenticationInfo.principalEmail:"@container-analysis.iam.gserviceaccount.com" OR protoPayload.authenticationInfo.principalEmail:"@gcp-sa-artifactregistry.iam.gserviceaccount.com" OR protoPayload.authenticationInfo.principalEmail:"@gcp-sa-containerscanning.iam.gserviceaccount.com" OR protoPayload.authenticationInfo.principalEmail:"@gcp-sa-ondemandscanning.iam.gserviceaccount.com" OR protoPayload.authenticationInfo.principalEmail:"@gcp-sa-containersec.iam.gserviceaccount.com" OR protoPayload.authenticationInfo.principalEmail=~"^config-sa-[0-9]+@")
  EOT
  )

  # Orchestrator service agent roles, keyed by the gcp-sa-<agent> token of the
  # agent's email.
  orchestrator_agent_roles = {
    "osconfig"         = "roles/osconfig.serviceAgent"
    "osconfig-rollout" = "roles/osconfig.rolloutServiceAgent"
    "progrollout"      = "roles/progressiverollout.serviceAgent"
  }

  target_orchestrator_bindings = {
    for pair in setproduct(tolist(local.vm_targets), keys(local.orchestrator_agent_roles)) :
    "${pair[0]}:${pair[1]}" => { project = pair[0], agent = pair[1], role = local.orchestrator_agent_roles[pair[1]] }
  }

  target_vm_apis = {
    for pair in setproduct(tolist(local.vm_targets), [
      "compute.googleapis.com", "osconfig.googleapis.com",
      "progressiverollout.googleapis.com", "serviceusage.googleapis.com",
    ]) : "${pair[0]}:${pair[1]}" => { project = pair[0], service = pair[1] }
  }
}

##################################################
# Custom roles and grants
##################################################
# No predefined role grants cloudfunctions.functions.sourceCodeGet without also
# granting deploy or modify.
resource "google_organization_iam_custom_role" "function_source" {
  count = local.any_inspector ? 1 : 0

  org_id      = local.org
  role_id     = local.inspector_function_source_role
  title       = "Inspector Function Source Reader"
  description = "Download Cloud Functions source for Amazon Inspector scanning."
  permissions = local.inspector_function_source_permissions
  stage       = "GA"

  depends_on = [terraform_data.preflight]
}

resource "google_organization_iam_custom_role" "vm_deployer" {
  count = local.any_inspector_vm ? 1 : 0

  org_id      = local.org
  role_id     = local.inspector_vm_deployer_role
  title       = "OS Policy SSM Deployer"
  description = "Can manage VM metadata, read VM properties, and create/manage OS Policy assignments for SSM deployment"
  stage       = "GA"
  permissions = local.inspector_vm_deployer_permissions

  depends_on = [terraform_data.preflight]
}

resource "google_organization_iam_member" "inspector_function_source" {
  for_each = local.inspector_accounts

  org_id = local.org
  role   = google_organization_iam_custom_role.function_source[0].name
  member = "serviceAccount:${google_service_account.connector[each.key].email}"
}

resource "google_organization_iam_member" "vm_deployer" {
  for_each = local.inspector_vm_accounts

  org_id = local.org
  role   = google_organization_iam_custom_role.vm_deployer[0].name
  member = "serviceAccount:${google_service_account.connector[each.key].email}"
}

##################################################
# Organization service agents
##################################################
# No provider resource creates an organization-scoped service identity, so
# gcloud creates it. gcloud runs with the google provider's own access token,
# so the active gcloud account cannot perform part of one apply. The token is
# sensitive, so Terraform suppresses the command output; on failure run the
# command by hand to see the gcloud error.
#
# The commands run under /bin/sh and use POSIX `set -eu` only.
data "google_client_config" "current" {}

resource "terraform_data" "org_service_agents" {
  count = local.any_inspector_vm ? 1 : 0

  triggers_replace = {
    organization = local.org
    project      = local.project
  }

  provisioner "local-exec" {
    environment = {
      CLOUDSDK_AUTH_ACCESS_TOKEN    = data.google_client_config.current.access_token
      CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
    }
    command = <<-EOT
      set -eu
      for svc in osconfig.googleapis.com progressiverollout.googleapis.com; do
        gcloud beta services identity create \
          --service="$svc" \
          --organization="${local.org}" \
          --billing-project="${local.project}" \
          --quiet
      done
    EOT
  }

  depends_on = [google_project_service.management_osconfig]
}

resource "google_organization_iam_member" "org_orchestrator_agent" {
  for_each = local.any_inspector_vm ? local.orchestrator_agent_roles : {}

  org_id = local.org
  role   = each.value
  member = "serviceAccount:service-org-${local.org}@gcp-sa-${each.key}.iam.gserviceaccount.com"

  depends_on = [terraform_data.org_service_agents]
}

##################################################
# VM target projects
##################################################
# An organization-scoped OS policy orchestrator needs the organization service
# agents and the service agents of each target project, so the module creates
# both.
data "google_project" "target" {
  for_each = local.vm_targets

  project_id = each.value
}

resource "google_project_service" "target_vm" {
  for_each = local.target_vm_apis

  project            = each.value.project
  service            = each.value.service
  disable_on_destroy = false

  depends_on = [terraform_data.preflight]
}

resource "terraform_data" "target_service_agents" {
  for_each = local.vm_targets

  triggers_replace = {
    project = each.value
  }

  provisioner "local-exec" {
    environment = {
      CLOUDSDK_AUTH_ACCESS_TOKEN    = data.google_client_config.current.access_token
      CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
    }
    command = <<-EOT
      set -eu
      for svc in osconfig.googleapis.com progressiverollout.googleapis.com; do
        gcloud beta services identity create \
          --service="$svc" \
          --project="${each.value}" \
          --quiet
      done
    EOT
  }

  depends_on = [google_project_service.target_vm]
}

resource "google_project_iam_member" "target_orchestrator_agent" {
  for_each = local.target_orchestrator_bindings

  project = each.value.project
  role    = each.value.role
  member  = "serviceAccount:service-${data.google_project.target[each.value.project].number}@gcp-sa-${each.value.agent}.iam.gserviceaccount.com"

  depends_on = [terraform_data.target_service_agents]
}

# Sets this one metadata key and keeps the other project metadata.
resource "google_compute_project_metadata_item" "target_enable_osconfig" {
  for_each = local.vm_targets

  project = each.value
  key     = "enable-osconfig"
  value   = "TRUE"

  depends_on = [google_project_service.target_vm]
}

# No provider resource sets the OS Config project feature settings, so gcloud
# sets the full VM Manager feature set.
resource "terraform_data" "target_vm_manager_full" {
  for_each = local.vm_targets

  triggers_replace = {
    project = each.value
  }

  provisioner "local-exec" {
    environment = {
      CLOUDSDK_AUTH_ACCESS_TOKEN    = data.google_client_config.current.access_token
      CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
    }
    command = <<-EOT
      set -eu
      gcloud compute os-config project-feature-settings update \
        --project="${each.value}" \
        --patch-and-config-feature-set=full \
        --quiet
    EOT
  }

  depends_on = [google_compute_project_metadata_item.target_enable_osconfig]
}

##################################################
# Image-pull log sink
##################################################
resource "google_pubsub_topic" "inspector_pull" {
  for_each = local.inspector_accounts

  project = local.project
  name    = each.value.inspector_pull_topic

  depends_on = [google_project_service.management]
}

resource "google_pubsub_subscription" "inspector_pull" {
  for_each = local.inspector_subscriptions

  project = local.project
  name    = each.value.inspector_pull
  topic   = google_pubsub_topic.inspector_pull[each.value.aws_account_id].id

  labels = {
    "aws-config-discovery" = each.value.discovery_label
  }

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription_iam_member" "inspector_pull_subscriber" {
  for_each = local.inspector_subscriptions

  project      = local.project
  subscription = google_pubsub_subscription.inspector_pull[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.connector[each.value.aws_account_id].email}"
}

resource "google_logging_organization_sink" "inspector_pull" {
  for_each = local.inspector_accounts

  name             = each.value.inspector_pull_sink
  org_id           = local.org
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.inspector_pull[each.key].id}"
  filter           = local.inspector_pull_filter
}

resource "google_pubsub_topic_iam_member" "inspector_pull_writer" {
  for_each = local.inspector_accounts

  project = local.project
  topic   = google_pubsub_topic.inspector_pull[each.key].name
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.inspector_pull[each.key].writer_identity
}
