mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "111111111111"
    }
  }

  mock_data "google_client_config" {
    defaults = {
      access_token = "mock-token"
    }
  }

  mock_data "google_organization_iam_policy" {
    defaults = {
      policy_data = "{}"
    }
  }

  mock_data "google_folder" {
    defaults = {
      organization = "organizations/123456789"
    }
  }

  # Default: the management project, ACTIVE, directly under the organization.
  mock_data "google_projects" {
    defaults = {
      projects = [{
        project_id      = "mgmt-project-1"
        number          = "111111111111"
        lifecycle_state = "ACTIVE"
        parent          = { type = "organization", id = "123456789" }
        name            = "mgmt"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }
}

mock_provider "google-beta" {}

# The VM target project, ACTIVE, under a folder of the organization.
override_data {
  target = data.google_projects.checked["target-project-1"]
  values = {
    projects = [{
      project_id      = "target-project-1"
      number          = "222222222222"
      lifecycle_state = "ACTIVE"
      parent          = { type = "folder", id = "555" }
      name            = "target"
      create_time     = "2026-01-01T00:00:00Z"
      labels          = {}
    }]
  }
}

override_data {
  target = data.google_project.target["target-project-1"]
  values = {
    number = "222222222222"
  }
}

variables {
  organization_id = "123456789"
  project_id      = "mgmt-project-1"
  onboarded_accounts = [{
    aws_account_id = "111122223333"
    aws_region     = "us-east-1"
    issuer_url     = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
  }]
}

run "config_only" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  assert {
    condition     = google_cloud_asset_organization_feed.cai["111122223333"].condition[0].expression == "!temporal_asset.asset.asset_type.startsWith(\"osconfig.googleapis.com/\")"
    error_message = "The Cloud Asset Inventory feed must drop osconfig.googleapis.com/* asset types."
  }
  assert {
    condition     = google_cloud_asset_organization_feed.cai["111122223333"].asset_types == tolist([".*"]) && google_cloud_asset_organization_feed.cai["111122223333"].content_type == "RESOURCE"
    error_message = "The feed must cover every other asset type with RESOURCE content."
  }
  assert {
    condition = google_iam_workload_identity_pool_provider.connector["111122223333"].attribute_condition == join("", [
      "attribute.aws_role in [",
      "'arn:aws:iam::111122223333:role/AWSConfigThirdPartyCloudFederationRole', ",
      "'arn:aws:iam::111122223333:role/aws-service-role/thirdparty.config.amazonaws.com/AWSServiceRoleForConfigThirdParty']",
    ])
    error_message = "Without Inspector the provider must trust exactly the two AWS Config subjects, in order."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.connector["111122223333"].oidc[0].allowed_audiences == tolist(["https://sts.googleapis.com"])
    error_message = "Without VM scanning the provider must allow only the STS audience."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.connector["111122223333"].oidc[0].issuer_uri == "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
    error_message = "The provider must trust the account's issuer."
  }
  assert {
    condition     = google_iam_workload_identity_pool.connector["111122223333"].workload_identity_pool_id == "connector-pool-111122223333" && google_service_account.connector["111122223333"].account_id == "config-sa-111122223333"
    error_message = "Pool and service account names must follow the connector templates."
  }
  assert {
    condition     = google_pubsub_subscription.lifecycle["111122223333-us-east-1"].labels["aws-config-discovery"] == "111122223333-us-east-1-mgmt-project-1"
    error_message = "The discovery label must be <account>-<region>-<management project>."
  }
  assert {
    condition     = length(keys(google_service_account_iam_member.impersonation)) == 2
    error_message = "Each trusted subject must get one impersonation binding."
  }
  assert {
    condition     = length(google_pubsub_subscription.inspector_pull) == 0 && length(google_organization_iam_custom_role.function_source) == 0 && length(google_organization_iam_audit_config.artifactregistry_read) == 0
    error_message = "Without Inspector the module must not create Inspector resources."
  }
  assert {
    condition     = length(terraform_data.org_service_agents) == 0 && length(terraform_data.target_service_agents) == 0
    error_message = "Without VM scanning the module must not run the gcloud commands."
  }
  assert {
    condition     = contains(keys(google_organization_iam_member.connector_read), "111122223333|roles/viewer")
    error_message = "The broad permission model must grant roles/viewer."
  }
  assert {
    condition     = [for c in google_organization_iam_audit_config.all_services_write.audit_log_config : c.log_type] == ["DATA_WRITE"]
    error_message = "allServices must enable DATA_WRITE."
  }
}

run "granular_permissions" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    permission_model = "granular"
  }

  assert {
    condition     = !contains(keys(google_organization_iam_member.connector_read), "111122223333|roles/viewer") && contains(keys(google_organization_iam_member.connector_read), "111122223333|roles/compute.viewer")
    error_message = "The granular permission model must grant per-service viewer roles instead of roles/viewer."
  }
  assert {
    condition     = length(google_organization_iam_member.connector_read) == 27
    error_message = "The granular permission model must grant 5 always-on and 22 per-service roles."
  }
}

# Each Region's Inspector subscription follows that Region's own flag.
run "inspector_subscription_per_region" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    onboarded_accounts = [
      {
        aws_account_id   = "111122223333"
        aws_region       = "us-east-1"
        issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
        enable_inspector = true
      },
      {
        aws_account_id   = "111122223333"
        aws_region       = "eu-west-1"
        issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
        enable_inspector = false
      },
    ]
  }

  assert {
    condition     = keys(google_pubsub_subscription.inspector_pull) == ["111122223333-us-east-1"]
    error_message = "Only the Region that enables Inspector may get an Inspector subscription."
  }
  assert {
    condition     = keys(google_pubsub_topic.inspector_pull) == ["111122223333"]
    error_message = "The account's Inspector topic must exist when any of its Regions enables Inspector."
  }
  assert {
    condition     = toset(keys(google_pubsub_subscription.lifecycle)) == toset(["111122223333-us-east-1", "111122223333-eu-west-1"]) && toset(keys(google_pubsub_subscription.cai)) == toset(["111122223333-us-east-1", "111122223333-eu-west-1"])
    error_message = "AWS Config subscriptions must exist in every Region."
  }
  assert {
    condition     = keys(google_iam_workload_identity_pool.connector) == ["111122223333"]
    error_message = "The pool is per account, not per Region."
  }
}

run "inspector_subjects" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition = google_iam_workload_identity_pool_provider.connector["111122223333"].attribute_condition == join("", [
      "attribute.aws_role in [",
      "'arn:aws:iam::111122223333:role/AWSConfigThirdPartyCloudFederationRole', ",
      "'arn:aws:iam::111122223333:role/aws-service-role/thirdparty.config.amazonaws.com/AWSServiceRoleForConfigThirdParty', ",
      "'arn:aws:iam::111122223333:role/aws-service-role/thirdparty.inspector2.amazonaws.com/AWSServiceRoleForAmazonInspector2ThirdParty']",
    ])
    error_message = "The Amazon Inspector service-linked role must be the third subject."
  }
  assert {
    condition     = contains(keys(google_service_account_iam_member.impersonation), "111122223333|arn:aws:iam::111122223333:role/aws-service-role/thirdparty.inspector2.amazonaws.com/AWSServiceRoleForAmazonInspector2ThirdParty")
    error_message = "The Inspector subject must get an impersonation binding."
  }
  assert {
    condition     = google_organization_iam_custom_role.function_source[0].permissions == toset(["cloudfunctions.functions.sourceCodeGet"])
    error_message = "The function source role must grant only cloudfunctions.functions.sourceCodeGet."
  }
  assert {
    condition     = [for c in google_organization_iam_audit_config.artifactregistry_read[0].audit_log_config : c.log_type] == ["DATA_READ"]
    error_message = "Inspector must enable Artifact Registry DATA_READ."
  }
  assert {
    condition     = length(google_organization_iam_custom_role.vm_deployer) == 0
    error_message = "Without target projects the module must not create the VM deployer role."
  }
}

run "vm_scanning" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition = google_organization_iam_custom_role.vm_deployer[0].permissions == toset([
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
    ])
    error_message = "OSPolicySSMDeployer must have exactly its 28 permissions."
  }
  assert {
    condition     = keys(terraform_data.target_service_agents) == ["target-project-1"] && keys(terraform_data.target_vm_manager_full) == ["target-project-1"] && length(terraform_data.org_service_agents) == 1
    error_message = "VM scanning must create the service agents and set VM Manager in each target project."
  }
  assert {
    condition     = google_project_iam_member.target_orchestrator_agent["target-project-1:osconfig"].member == "serviceAccount:service-222222222222@gcp-sa-osconfig.iam.gserviceaccount.com"
    error_message = "Target orchestrator grants must use the target project number, not the management project number."
  }
  assert {
    condition     = google_organization_iam_member.org_orchestrator_agent["progrollout"].member == "serviceAccount:service-org-123456789@gcp-sa-progrollout.iam.gserviceaccount.com"
    error_message = "Organization orchestrator grants must use the organization service agents."
  }
  assert {
    condition     = google_compute_project_metadata_item.target_enable_osconfig["target-project-1"].value == "TRUE"
    error_message = "VM scanning must set enable-osconfig in each target project."
  }
  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.connector["111122223333"].attribute_condition, "'arn:aws:iam::111122223333:role/Inspector2SSMFederationRole-123456789']")
    error_message = "VM scanning must trust the account's Inspector2SSMFederationRole-<organization> as the last subject."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.connector["111122223333"].oidc[0].allowed_audiences == tolist(["https://sts.googleapis.com", "api://AWSTokenExchange"])
    error_message = "VM scanning must also allow the api://AWSTokenExchange audience."
  }
}

# VM trust is per account: two Inspector accounts share one target list, and
# only the account that opts in gets VM scanning trust and the deployer grant.
run "vm_trust_per_account" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
    onboarded_accounts = [
      {
        aws_account_id   = "111122223333"
        aws_region       = "us-east-1"
        issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
        enable_inspector = true
      },
      {
        aws_account_id      = "444455556666"
        aws_region          = "us-east-1"
        issuer_url          = "https://00000000-0000-4000-8000-000000000002.tokens.sts.global.api.aws"
        enable_inspector    = true
        enable_inspector_vm = false
      },
    ]
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.connector["111122223333"].attribute_condition, "Inspector2SSMFederationRole-123456789")
    error_message = "The account that opts in must trust its VM scanning role."
  }
  assert {
    condition     = !strcontains(google_iam_workload_identity_pool_provider.connector["444455556666"].attribute_condition, "Inspector2SSMFederationRole")
    error_message = "An Inspector account with enable_inspector_vm = false must not trust a VM scanning role."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.connector["444455556666"].oidc[0].allowed_audiences == tolist(["https://sts.googleapis.com"])
    error_message = "An account without VM scanning must not allow api://AWSTokenExchange."
  }
  assert {
    condition     = keys(google_organization_iam_member.vm_deployer) == ["111122223333"]
    error_message = "Only the account that opts in may get the VM deployer grant."
  }
}

# The audit configuration keeps the log types and exemptions that are already set.
run "audit_merge_keeps_existing" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  override_data {
    target = data.google_organization_iam_policy.organization
    values = {
      policy_data = "{\"auditConfigs\":[{\"service\":\"allServices\",\"auditLogConfigs\":[{\"logType\":\"ADMIN_READ\",\"exemptedMembers\":[\"user:admin@example.com\"]}]}]}"
    }
  }

  assert {
    condition     = toset([for c in google_organization_iam_audit_config.all_services_write.audit_log_config : c.log_type]) == toset(["ADMIN_READ", "DATA_WRITE"])
    error_message = "The audit configuration must keep the existing log types and add DATA_WRITE."
  }
  assert {
    condition     = one([for c in google_organization_iam_audit_config.all_services_write.audit_log_config : c.exempted_members if c.log_type == "ADMIN_READ"]) == toset(["user:admin@example.com"])
    error_message = "The audit configuration must keep the existing exemptions."
  }
}

run "rejects_required_audit_exemption" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  override_data {
    target = data.google_organization_iam_policy.organization
    values = {
      policy_data = "{\"auditConfigs\":[{\"service\":\"storage.googleapis.com\",\"auditLogConfigs\":[{\"logType\":\"DATA_WRITE\",\"exemptedMembers\":[\"user:admin@example.com\"]}]}]}"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "healthy_target_under_folder" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition     = length(local.project_defects) == 0
    error_message = "An ACTIVE target under a folder of the organization must pass the project check."
  }
}

run "rejects_management_project_in_other_organization" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  override_data {
    target = data.google_projects.checked["mgmt-project-1"]
    values = {
      projects = [{
        project_id      = "mgmt-project-1"
        number          = "111111111111"
        lifecycle_state = "ACTIVE"
        parent          = { type = "organization", id = "999999999" }
        name            = "mgmt"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "rejects_missing_management_project" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  override_data {
    target = data.google_projects.checked["mgmt-project-1"]
    values = {
      projects = []
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "rejects_target_under_folder_of_other_organization" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  override_data {
    target = data.google_folder.parent["target-project-1"]
    values = {
      organization = "organizations/999999999"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "rejects_inactive_target" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  override_data {
    target = data.google_projects.checked["target-project-1"]
    values = {
      projects = [{
        project_id      = "target-project-1"
        number          = "222222222222"
        lifecycle_state = "DELETE_REQUESTED"
        parent          = { type = "organization", id = "123456789" }
        name            = "target"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "rejects_targets_without_inspector" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    target_project_ids = ["target-project-1"]
  }

  expect_failures = [var.target_project_ids]
}

run "rejects_conflicting_issuers" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    onboarded_accounts = [
      {
        aws_account_id = "111122223333"
        aws_region     = "us-east-1"
        issuer_url     = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      },
      {
        aws_account_id = "111122223333"
        aws_region     = "us-west-2"
        issuer_url     = "https://00000000-0000-4000-8000-000000000002.tokens.sts.global.api.aws"
      },
    ]
  }

  expect_failures = [var.onboarded_accounts]
}

run "rejects_invalid_issuer" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    onboarded_accounts = [{
      aws_account_id = "111122223333"
      aws_region     = "us-east-1"
      issuer_url     = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws/path"
    }]
  }

  expect_failures = [var.onboarded_accounts]
}
