mock_provider "google" {
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

# Service identities as the API returns them.
override_resource {
  override_during = plan
  target          = google_organization_service_identity.orchestrator["osconfig.googleapis.com"]
  values = {
    email  = "service-org-123456789@gcp-sa-osconfig.iam.gserviceaccount.com"
    member = "serviceAccount:service-org-123456789@gcp-sa-osconfig.iam.gserviceaccount.com"
  }
}

override_resource {
  override_during = plan
  target          = google_organization_service_identity.orchestrator["progressiverollout.googleapis.com"]
  values = {
    email  = "service-org-123456789@gcp-sa-progrollout.iam.gserviceaccount.com"
    member = "serviceAccount:service-org-123456789@gcp-sa-progrollout.iam.gserviceaccount.com"
  }
}

override_resource {
  override_during = plan
  target          = google_project_service_identity.target_orchestrator["target-project-1:osconfig.googleapis.com"]
  values = {
    email  = "service-222222222222@gcp-sa-osconfig.iam.gserviceaccount.com"
    member = "serviceAccount:service-222222222222@gcp-sa-osconfig.iam.gserviceaccount.com"
  }
}

override_resource {
  override_during = plan
  target          = google_project_service_identity.target_orchestrator["target-project-1:progressiverollout.googleapis.com"]
  values = {
    email  = "service-222222222222@gcp-sa-progrollout.iam.gserviceaccount.com"
    member = "serviceAccount:service-222222222222@gcp-sa-progrollout.iam.gserviceaccount.com"
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
    condition     = length(google_organization_service_identity.orchestrator) == 0 && length(google_project_service_identity.target_orchestrator) == 0 && length(data.google_client_config.current) == 0
    error_message = "Without VM scanning the module must not create the OS Config service identities or read the access token."
  }
  assert {
    condition     = contains(keys(google_organization_iam_member.connector_read), "111122223333|roles/viewer")
    error_message = "The broad permission model must grant roles/viewer."
  }
  assert {
    condition     = [for c in google_organization_iam_audit_config.all_services_write[0].audit_log_config : c.log_type] == ["DATA_WRITE"]
    error_message = "allServices must enable DATA_WRITE."
  }
  assert {
    condition     = google_pubsub_topic.lifecycle["111122223333"].kms_key_name == null && length(google_kms_crypto_key_iam_member.pubsub_agent) == 0 && length(google_project_service_identity.pubsub) == 0
    error_message = "Without pubsub_kms_key_name the topics must use Google-managed encryption and the module must not grant a key."
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
    condition     = length(google_organization_iam_custom_role.vm_deployer) == 0 && length(google_organization_iam_custom_role.vm_orchestrator) == 0
    error_message = "Without target projects the module must not create the VM roles."
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
    condition = google_organization_iam_custom_role.vm_orchestrator[0].permissions == toset([
      "cloudasset.assets.searchAllResources",
      "compute.instances.get",
      "compute.instances.list",
      "compute.projects.get",
      "compute.regions.get",
      "compute.zoneOperations.get",
      "osconfig.inventories.get",
      "osconfig.inventories.list",
      "osconfig.operations.get",
      "osconfig.operations.list",
      "osconfig.osPolicyAssignmentReports.get",
      "osconfig.osPolicyAssignmentReports.list",
      "osconfig.osPolicyAssignments.get",
      "osconfig.osPolicyAssignments.list",
      "osconfig.policyOrchestrators.create",
      "osconfig.policyOrchestrators.delete",
      "osconfig.policyOrchestrators.get",
      "osconfig.policyOrchestrators.list",
      "osconfig.policyOrchestrators.update",
      "resourcemanager.projects.get",
      "serviceusage.services.get",
      "serviceusage.services.list",
    ])
    error_message = "OSPolicySSMOrchestrator must have exactly its 22 permissions, none of which changes a VM."
  }
  # Default vm_orchestrator_parent = "organization": no project-level orchestrator grant.
  assert {
    condition     = length(google_organization_iam_custom_role.vm_project_orchestrator) == 0 && length(google_project_iam_member.vm_project_orchestrator) == 0 && keys(google_organization_iam_member.vm_orchestrator) == ["111122223333"]
    error_message = "With vm_orchestrator_parent = organization the orchestrator permissions must be granted only at the organization."
  }
  assert {
    condition = google_organization_iam_custom_role.vm_deployer[0].permissions == toset([
      "compute.instances.setLabels",
      "compute.instances.setMetadata",
      "iam.serviceAccounts.actAs",
      "osconfig.osPolicyAssignments.create",
      "osconfig.osPolicyAssignments.delete",
      "osconfig.osPolicyAssignments.update",
    ])
    error_message = "OSPolicySSMTargetDeployer must have exactly its 6 VM write permissions."
  }
  # The VM write permissions must never be granted at the organization.
  assert {
    condition     = length(setintersection(google_organization_iam_custom_role.vm_orchestrator[0].permissions, google_organization_iam_custom_role.vm_deployer[0].permissions)) == 0 && length(setintersection(google_organization_iam_custom_role.vm_orchestrator[0].permissions, toset(["compute.instances.setMetadata", "compute.instances.setLabels", "iam.serviceAccounts.actAs", "osconfig.osPolicyAssignments.create", "osconfig.osPolicyAssignments.update", "osconfig.osPolicyAssignments.delete"]))) == 0
    error_message = "No organization grant may carry setMetadata, setLabels, actAs or OS policy assignment writes."
  }
  assert {
    condition     = keys(google_project_iam_member.vm_deployer) == ["target-project-1|111122223333"] && google_project_iam_member.vm_deployer["target-project-1|111122223333"].project == "target-project-1"
    error_message = "The VM deployer role must be granted once per target project and VM scanning account, in the target project."
  }
  assert {
    condition     = toset(keys(google_project_service_identity.target_orchestrator)) == toset(["target-project-1:osconfig.googleapis.com", "target-project-1:progressiverollout.googleapis.com"]) && toset(keys(google_organization_service_identity.orchestrator)) == toset(["osconfig.googleapis.com", "progressiverollout.googleapis.com"]) && keys(terraform_data.target_vm_manager_full) == ["target-project-1"]
    error_message = "VM scanning must create the organization and target service identities and set VM Manager in each target project."
  }
  assert {
    condition     = google_project_iam_member.target_orchestrator_agent["target-project-1:osconfig"].member == "serviceAccount:service-222222222222@gcp-sa-osconfig.iam.gserviceaccount.com"
    error_message = "Target orchestrator grants must use the target project number, not the management project number."
  }
  assert {
    condition     = google_organization_iam_member.org_orchestrator_agent["progrollout"].member == "serviceAccount:service-org-123456789@gcp-sa-progrollout.iam.gserviceaccount.com" && google_organization_iam_member.org_orchestrator_agent["osconfig-rollout"].member == "serviceAccount:service-org-123456789@gcp-sa-osconfig-rollout.iam.gserviceaccount.com"
    error_message = "Organization orchestrator grants must use the organization service agents."
  }
  assert {
    condition     = google_project_iam_member.target_orchestrator_agent["target-project-1:osconfig-rollout"].member == "serviceAccount:service-222222222222@gcp-sa-osconfig-rollout.iam.gserviceaccount.com"
    error_message = "The target rollout agent must use the target project number from the preflight record."
  }
  assert {
    condition     = output.service_agents.target_projects["target-project-1"].osconfig_rollout == "service-222222222222@gcp-sa-osconfig-rollout.iam.gserviceaccount.com" && output.service_agents.organization.osconfig == "service-org-123456789@gcp-sa-osconfig.iam.gserviceaccount.com"
    error_message = "The outputs must report the organization and target service agents."
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
    condition = google_iam_workload_identity_pool_provider.connector["111122223333"].oidc[0].allowed_audiences == tolist([
      "https://sts.googleapis.com",
      "api://AWSTokenExchange",
    ])
    error_message = "VM scanning must retain both SSM transition audiences until the rollout is complete in every Region."
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
    enable_inspector_vm_bridge = true
    target_project_ids         = ["target-project-1"]
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
    error_message = "An account without VM scanning must allow only the STS audience."
  }
  assert {
    condition     = keys(google_iam_workload_identity_pool.bridge) == ["111122223333"]
    error_message = "Only the account that opts into VM scanning may get a credential bridge."
  }
  assert {
    condition     = keys(google_service_account.minter) == ["target-project-1|111122223333"]
    error_message = "A non-VM-scanning account must not get a minter service account."
  }
  assert {
    condition     = keys(google_organization_iam_member.vm_orchestrator) == ["111122223333"] && keys(google_project_iam_member.vm_deployer) == ["target-project-1|111122223333"]
    error_message = "Only the account that opts in may get the VM orchestrator and deployer grants."
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
    condition     = toset([for c in google_organization_iam_audit_config.all_services_write[0].audit_log_config : c.log_type]) == toset(["ADMIN_READ", "DATA_WRITE"])
    error_message = "The audit configuration must keep the existing log types and add DATA_WRITE."
  }
  assert {
    condition     = one([for c in google_organization_iam_audit_config.all_services_write[0].audit_log_config : c.exempted_members if c.log_type == "ADMIN_READ"]) == toset(["user:admin@example.com"])
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

# The management project number comes from the preflight project record, not
# from a google_project data source that would fail first on a missing project.
run "project_number_from_preflight_record" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  override_data {
    target = data.google_projects.checked["mgmt-project-1"]
    values = {
      projects = [{
        project_id      = "mgmt-project-1"
        number          = "333333333333"
        lifecycle_state = "ACTIVE"
        parent          = { type = "organization", id = "123456789" }
        name            = "mgmt"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }

  assert {
    condition     = output.project_number == "333333333333"
    error_message = "The project number must come from the google_projects record."
  }
  assert {
    condition     = startswith(google_service_account_iam_member.impersonation["111122223333|arn:aws:iam::111122223333:role/AWSConfigThirdPartyCloudFederationRole"].member, "principalSet://iam.googleapis.com/projects/333333333333/")
    error_message = "The principalSet path must use the project number from the google_projects record."
  }
}

run "outputs" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  assert {
    condition     = output.custom_roles.vm_deployer == null && output.custom_roles.vm_orchestrator == null && output.service_agents.organization.osconfig_rollout == null && output.service_agents.pubsub == null
    error_message = "Roles and agents that the module does not create must be null."
  }
  assert {
    condition     = output.accounts["111122223333"].inspector_pull_sink_writer_identity == null
    error_message = "Without Inspector the image-pull sink writer identity must be null."
  }
}

run "kms_key" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    pubsub_kms_key_name = "projects/kms-project/locations/us/keyRings/ring/cryptoKeys/key"
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition = alltrue([
      google_pubsub_topic.lifecycle["111122223333"].kms_key_name == "projects/kms-project/locations/us/keyRings/ring/cryptoKeys/key",
      google_pubsub_topic.cai["111122223333"].kms_key_name == "projects/kms-project/locations/us/keyRings/ring/cryptoKeys/key",
      google_pubsub_topic.inspector_pull["111122223333"].kms_key_name == "projects/kms-project/locations/us/keyRings/ring/cryptoKeys/key",
    ])
    error_message = "All three topics must use the key."
  }
  assert {
    condition     = google_kms_crypto_key_iam_member.pubsub_agent[0].crypto_key_id == "projects/kms-project/locations/us/keyRings/ring/cryptoKeys/key" && google_kms_crypto_key_iam_member.pubsub_agent[0].role == "roles/cloudkms.cryptoKeyEncrypterDecrypter" && google_project_service_identity.pubsub[0].service == "pubsub.googleapis.com"
    error_message = "The management project's Pub/Sub service agent must get encrypter/decrypter on the key."
  }
}

run "rejects_invalid_kms_key" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    pubsub_kms_key_name = "key"
  }

  expect_failures = [var.pubsub_kms_key_name]
}

# Another configuration owns the audit configuration and already enables what
# the connector needs.
run "audit_unmanaged" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    manage_audit_config = false
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  override_data {
    target = data.google_organization_iam_policy.organization
    values = {
      policy_data = "{\"auditConfigs\":[{\"service\":\"allServices\",\"auditLogConfigs\":[{\"logType\":\"DATA_WRITE\"}]},{\"service\":\"artifactregistry.googleapis.com\",\"auditLogConfigs\":[{\"logType\":\"DATA_READ\"}]}]}"
    }
  }

  assert {
    condition     = length(google_organization_iam_audit_config.all_services_write) == 0 && length(google_organization_iam_audit_config.artifactregistry_read) == 0
    error_message = "With manage_audit_config = false the module must not create an audit configuration."
  }
}

run "rejects_unmanaged_audit_missing_log_type" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    manage_audit_config = false
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  # allServices DATA_WRITE is on; Artifact Registry DATA_READ is not.
  override_data {
    target = data.google_organization_iam_policy.organization
    values = {
      policy_data = "{\"auditConfigs\":[{\"service\":\"allServices\",\"auditLogConfigs\":[{\"logType\":\"DATA_WRITE\"}]}]}"
    }
  }

  expect_failures = [terraform_data.preflight]
}

# vm_orchestrator_parent = "project": orchestrator writes only in the
# management project, reads still at the organization.
run "vm_orchestrator_parent_project" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    vm_orchestrator_parent = "project"
    target_project_ids     = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition     = length([for p in google_organization_iam_custom_role.vm_orchestrator[0].permissions : p if startswith(p, "osconfig.policyOrchestrators.")]) == 0 && length(google_organization_iam_custom_role.vm_orchestrator[0].permissions) == 17
    error_message = "With vm_orchestrator_parent = project the organization role must hold only the 17 read-only permissions."
  }
  assert {
    condition = google_organization_iam_custom_role.vm_project_orchestrator[0].permissions == toset([
      "osconfig.policyOrchestrators.create",
      "osconfig.policyOrchestrators.delete",
      "osconfig.policyOrchestrators.get",
      "osconfig.policyOrchestrators.list",
      "osconfig.policyOrchestrators.update",
    ])
    error_message = "OSPolicySSMProjectOrchestrator must hold exactly the five policyOrchestrators permissions."
  }
  assert {
    condition     = keys(google_project_iam_member.vm_project_orchestrator) == ["111122223333"] && google_project_iam_member.vm_project_orchestrator["111122223333"].project == "mgmt-project-1"
    error_message = "The orchestrator permissions must be granted in the management project, once per VM scanning account."
  }
  assert {
    condition     = keys(google_organization_iam_member.vm_orchestrator) == ["111122223333"] && keys(google_project_iam_member.vm_deployer) == ["target-project-1|111122223333"]
    error_message = "The organization read grant and the target deployer grant must not change."
  }
}

run "rejects_invalid_vm_orchestrator_parent" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    vm_orchestrator_parent = "folder"
  }

  expect_failures = [var.vm_orchestrator_parent]
}

# The Inspector VM credential bridge, with two target projects whose numbers
# are listed out of order.
run "vm_bridge" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    enable_inspector_vm_bridge = true
    target_project_ids         = ["target-project-1", "target-project-2"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  override_data {
    target = data.google_projects.checked["target-project-2"]
    values = {
      projects = [{
        project_id      = "target-project-2"
        number          = "100000000000"
        lifecycle_state = "ACTIVE"
        parent          = { type = "organization", id = "123456789" }
        name            = "target2"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool.bridge["111122223333"].workload_identity_pool_id == "inspector-vm-bridge-111122223333" && google_iam_workload_identity_pool.bridge["111122223333"].project == "mgmt-project-1" && length(google_iam_workload_identity_pool.bridge["111122223333"].display_name) <= 32
    error_message = "The bridge pool must be inspector-vm-bridge-<account> in the management project, with a display name of at most 32 characters."
  }
  assert {
    condition = google_iam_workload_identity_pool_provider.bridge["111122223333"].attribute_mapping == tomap({
      "google.subject"           = "assertion.sub"
      "attribute.project_id"     = "assertion.google.compute_engine.project_id"
      "attribute.project_number" = "string(int(assertion.google.compute_engine.project_number))"
      "attribute.instance_id"    = "assertion.google.compute_engine.instance_id"
      "attribute.sa_email"       = "assertion.email"
    })
    error_message = "The bridge provider must have exactly the five attribute mappings of the setup script."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.bridge["111122223333"].attribute_condition == "attribute.project_number in ['100000000000', '222222222222'] && attribute.instance_id != ''"
    error_message = "The bridge condition must list the target project numbers sorted and quoted, and require an instance ID."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.bridge["111122223333"].workload_identity_pool_provider_id == "compute-engine-vm" && google_iam_workload_identity_pool_provider.bridge["111122223333"].oidc[0].issuer_uri == "https://accounts.google.com" && google_iam_workload_identity_pool_provider.bridge["111122223333"].oidc[0].allowed_audiences == tolist(["https://iam.googleapis.com/projects/111111111111/locations/global/workloadIdentityPools/inspector-vm-bridge-111122223333/providers/compute-engine-vm"])
    error_message = "The bridge provider must be compute-engine-vm, trust only accounts.google.com, and allow exactly its own full audience with the management project number."
  }
  assert {
    condition     = output.inspector_vm_bridge["111122223333"].audience == "https://iam.googleapis.com/projects/111111111111/locations/global/workloadIdentityPools/inspector-vm-bridge-111122223333/providers/compute-engine-vm"
    error_message = "The bridge audience output must equal the provider's allowed audience."
  }
  assert {
    condition     = !output.inspector_vm_bridge["111122223333"].uses_any_vm_fallback
    error_message = "A bounded target list must report that it does not use the any-VM fallback."
  }
  assert {
    condition     = toset(keys(google_service_account.minter)) == toset(["target-project-1|111122223333", "target-project-2|111122223333"]) && google_service_account.minter["target-project-1|111122223333"].project == "target-project-1" && google_service_account.minter["target-project-1|111122223333"].account_id == "inspector-vmscan-111122223333"
    error_message = "Each target project must get its own minter inspector-vmscan-<account>, in that project."
  }
  assert {
    condition     = google_service_account_iam_member.minter_token_creator["target-project-2|111122223333"].member == "principalSet://iam.googleapis.com/projects/111111111111/locations/global/workloadIdentityPools/inspector-vm-bridge-111122223333/attribute.project_id/target-project-2" && google_service_account_iam_member.minter_token_creator["target-project-2|111122223333"].role == "roles/iam.serviceAccountOpenIdTokenCreator"
    error_message = "The minter binding must grant token creator to the bridge principal set of its own project, with the management project number."
  }
  assert {
    condition     = alltrue([for b in google_service_account_iam_member.minter_token_creator : length(b.condition) == 0])
    error_message = "The minter bindings must have no IAM condition."
  }
  assert {
    condition     = contains(keys(google_project_service.target_vm), "target-project-2:iam.googleapis.com") && contains(keys(google_project_service.target_vm), "target-project-2:iamcredentials.googleapis.com")
    error_message = "The bridge must enable IAM and IAM Credentials in each target project."
  }
}

# Over 4096 characters the condition admits any Compute Engine VM token.
run "vm_bridge_condition_fallback" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    enable_inspector_vm_bridge = true
    target_project_ids         = [for i in range(260) : format("target-project-%03d", i)]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  override_data {
    target = data.google_projects.checked
    values = {
      # The management project and target-project-000 to target-project-259.
      # Override values cannot call functions, so the suffixes are listed.
      projects = [for i in [
        "mgmt",
        "000", "001", "002", "003", "004", "005", "006", "007", "008", "009", "010", "011", "012",
        "013", "014", "015", "016", "017", "018", "019", "020", "021", "022", "023", "024", "025",
        "026", "027", "028", "029", "030", "031", "032", "033", "034", "035", "036", "037", "038",
        "039", "040", "041", "042", "043", "044", "045", "046", "047", "048", "049", "050", "051",
        "052", "053", "054", "055", "056", "057", "058", "059", "060", "061", "062", "063", "064",
        "065", "066", "067", "068", "069", "070", "071", "072", "073", "074", "075", "076", "077",
        "078", "079", "080", "081", "082", "083", "084", "085", "086", "087", "088", "089", "090",
        "091", "092", "093", "094", "095", "096", "097", "098", "099", "100", "101", "102", "103",
        "104", "105", "106", "107", "108", "109", "110", "111", "112", "113", "114", "115", "116",
        "117", "118", "119", "120", "121", "122", "123", "124", "125", "126", "127", "128", "129",
        "130", "131", "132", "133", "134", "135", "136", "137", "138", "139", "140", "141", "142",
        "143", "144", "145", "146", "147", "148", "149", "150", "151", "152", "153", "154", "155",
        "156", "157", "158", "159", "160", "161", "162", "163", "164", "165", "166", "167", "168",
        "169", "170", "171", "172", "173", "174", "175", "176", "177", "178", "179", "180", "181",
        "182", "183", "184", "185", "186", "187", "188", "189", "190", "191", "192", "193", "194",
        "195", "196", "197", "198", "199", "200", "201", "202", "203", "204", "205", "206", "207",
        "208", "209", "210", "211", "212", "213", "214", "215", "216", "217", "218", "219", "220",
        "221", "222", "223", "224", "225", "226", "227", "228", "229", "230", "231", "232", "233",
        "234", "235", "236", "237", "238", "239", "240", "241", "242", "243", "244", "245", "246",
        "247", "248", "249", "250", "251", "252", "253", "254", "255", "256", "257", "258", "259",
        ] : {
        project_id      = i == "mgmt" ? "mgmt-project-1" : "target-project-${i}"
        number          = i == "mgmt" ? "111111111111" : "300000000${i}"
        lifecycle_state = "ACTIVE"
        parent          = { type = "organization", id = "123456789" }
        name            = "project"
        create_time     = "2026-01-01T00:00:00Z"
        labels          = {}
      }]
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.bridge["111122223333"].attribute_condition == "attribute.project_number != '' && attribute.instance_id != ''"
    error_message = "A project list over 4096 characters must use the any-VM fallback condition."
  }
  assert {
    condition     = output.inspector_vm_bridge["111122223333"].uses_any_vm_fallback
    error_message = "The bridge output must report when the provider uses the any-VM fallback."
  }
}

run "vm_bridge_off" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    enable_inspector_vm_bridge = false
    target_project_ids         = ["target-project-1"]
    onboarded_accounts = [{
      aws_account_id   = "111122223333"
      aws_region       = "us-east-1"
      issuer_url       = "https://00000000-0000-4000-8000-000000000001.tokens.sts.global.api.aws"
      enable_inspector = true
    }]
  }

  assert {
    condition     = length(google_iam_workload_identity_pool.bridge) == 0 && length(google_iam_workload_identity_pool_provider.bridge) == 0 && length(google_service_account.minter) == 0 && length(google_service_account_iam_member.minter_token_creator) == 0 && output.inspector_vm_bridge == {}
    error_message = "With enable_inspector_vm_bridge = false the module must not create the bridge."
  }
  assert {
    condition     = !contains(keys(google_project_service.target_vm), "target-project-1:iamcredentials.googleapis.com") && keys(google_project_iam_member.vm_deployer) == ["target-project-1|111122223333"]
    error_message = "Without the bridge VM scanning must not change and must not enable IAM Credentials in the target project."
  }
}

# accounts[*].cai_feed is the configured feed name because imported feed_id
# can remain null. The output block explicitly depends on the feed resources.
run "cai_feed_output" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  assert {
    condition     = output.accounts["111122223333"].cai_feed == "config-cai-feed-111122223333"
    error_message = "accounts[*].cai_feed must use the configured feed name."
  }
  assert {
    condition     = length(google_iam_workload_identity_pool.bridge) == 0 && output.inspector_vm_bridge == {}
    error_message = "Without VM scanning the module must not create the bridge."
  }
}
