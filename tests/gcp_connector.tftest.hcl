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

# The custom role name as the API returns it.
override_resource {
  override_during = plan
  target          = google_organization_iam_custom_role.config_reader
  values = {
    name = "organizations/123456789/roles/securityHubConfigReader"
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
    condition     = length(google_pubsub_subscription.inspector_pull) == 0 && length(google_organization_iam_custom_role.function_source) == 0 && length(google_organization_iam_custom_role.artifact_reader) == 0 && length(google_organization_iam_audit_config.artifactregistry_read) == 0
    error_message = "Without Inspector the module must not create Inspector resources."
  }
  assert {
    condition     = length(google_organization_service_identity.orchestrator) == 0 && length(google_project_service_identity.target_orchestrator) == 0 && length(data.google_client_config.current) == 0
    error_message = "Without VM scanning the module must not create the OS Config service identities or read the access token."
  }
  assert {
    condition     = toset(keys(google_organization_iam_member.connector_read)) == toset(["111122223333|securityHubConfigReader", "111122223333|roles/cloudasset.viewer", "111122223333|roles/serviceusage.serviceUsageConsumer", "111122223333|roles/browser", "111122223333|roles/pubsub.viewer"])
    error_message = "The connector must get exactly the Config reader custom role and the four always-on roles at the organization."
  }
  assert {
    condition     = google_organization_iam_custom_role.config_reader.role_id == "securityHubConfigReader" && google_organization_iam_custom_role.config_reader.org_id == "123456789" && google_organization_iam_custom_role.config_reader.title == "Security Hub Config Reader"
    error_message = "The Config reader custom role must be securityHubConfigReader at the organization."
  }
  assert {
    condition     = length(google_organization_iam_custom_role.config_reader.permissions) == 206
    error_message = "The Config reader custom role must hold exactly 206 permissions."
  }
  assert {
    condition     = sort(local.config_reader_permissions) == tolist(local.config_reader_permissions) && length(google_organization_iam_custom_role.config_reader.permissions) == length(local.config_reader_permissions) && length(distinct(local.config_reader_permissions)) == length(local.config_reader_permissions)
    error_message = "The Config reader permission list must be sorted and have no duplicates."
  }
  assert {
    condition     = sha256(join(",", local.config_reader_permissions)) == "e5f378c7f0d14a511fe217b33f0bd082c5d60dd657a377394102e1ac414a8399"
    error_message = "The Config reader permission list changed. Update the digest only together with a reviewed change to the list."
  }
  assert {
    condition = length(setintersection(google_organization_iam_custom_role.config_reader.permissions, toset([
      "artifactregistry.repositories.downloadArtifacts",
      "bigquery.tables.getData",
      "cloudfunctions.functions.sourceCodeGet",
      "secretmanager.versions.access",
      "storage.objects.get",
      "storage.objects.list",
    ]))) == 0
    error_message = "The Config reader custom role must not read object bytes, table rows, secret values, image contents or function source."
  }
  assert {
    condition     = alltrue([for g in google_organization_iam_member.connector_read : !contains(["roles/viewer", "roles/iam.securityReviewer", "roles/artifactregistry.reader"], g.role)])
    error_message = "The connector must not get roles/viewer, roles/iam.securityReviewer or roles/artifactregistry.reader."
  }
  assert {
    condition     = toset(keys(google_project_service.management)) == toset(["accesscontextmanager.googleapis.com", "apikeys.googleapis.com", "appengine.googleapis.com", "artifactregistry.googleapis.com", "bigquery.googleapis.com", "cloudasset.googleapis.com", "cloudfunctions.googleapis.com", "cloudkms.googleapis.com", "cloudresourcemanager.googleapis.com", "compute.googleapis.com", "container.googleapis.com", "dataproc.googleapis.com", "dlp.googleapis.com", "dns.googleapis.com", "eventarc.googleapis.com", "firestore.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com", "orgpolicy.googleapis.com", "pubsub.googleapis.com", "run.googleapis.com", "secretmanager.googleapis.com", "serviceusage.googleapis.com", "sqladmin.googleapis.com", "sts.googleapis.com", "storage.googleapis.com", "vpcaccess.googleapis.com"])
    error_message = "The management project must enable exactly the connector APIs."
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

run "config_reader_role_id" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    config_reader_role_id = "customConfigReader"
  }

  assert {
    condition     = google_organization_iam_custom_role.config_reader.role_id == "customConfigReader" && contains(keys(google_organization_iam_member.connector_read), "111122223333|customConfigReader")
    error_message = "config_reader_role_id must name the Config reader custom role and its grant."
  }
}

run "rejects_invalid_config_reader_role_id" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    config_reader_role_id = "bad-role-id"
  }

  expect_failures = [var.config_reader_role_id]
}

run "config_reader_role_id_clashes_with_inspector_role" {
  module {
    source = "./modules/gcp_connector"
  }

  command = plan

  variables {
    config_reader_role_id = "inspectorArtifactReader"
  }

  expect_failures = [var.config_reader_role_id]
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
    condition     = google_organization_iam_custom_role.artifact_reader[0].role_id == "inspectorArtifactReader" && google_organization_iam_custom_role.artifact_reader[0].permissions == toset(["artifactregistry.repositories.downloadArtifacts"])
    error_message = "The artifact reader role must be inspectorArtifactReader with only artifactregistry.repositories.downloadArtifacts."
  }
  assert {
    condition     = keys(google_organization_iam_member.inspector_artifact_reader) == ["111122223333"] && keys(google_organization_iam_member.inspector_function_source) == ["111122223333"]
    error_message = "Each Inspector account must get the artifact reader and function source roles at the organization."
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
    condition     = google_iam_workload_identity_pool_provider.connector["111122223333"].oidc[0].allowed_audiences == tolist(["https://sts.googleapis.com"])
    error_message = "With VM scanning the provider must still allow only the STS audience."
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
    error_message = "An account without VM scanning must allow only the STS audience."
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
