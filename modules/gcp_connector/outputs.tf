output "accounts" {
  description = "Per-account resources, keyed by AWS account ID. `workload_identity_audience` is the exact audience for the token exchange. The sink writer identities are the principals that publish to the topics."
  value = {
    for id, n in local.account_names : id => {
      cai_feed                            = google_cloud_asset_organization_feed.cai[id].feed_id
      cai_topic                           = google_pubsub_topic.cai[id].name
      inspector_pull_sink_writer_identity = try(google_logging_organization_sink.inspector_pull[id].writer_identity, null)
      inspector_pull_topic                = try(google_pubsub_topic.inspector_pull[id].name, null)
      lifecycle_sink_writer_identity      = google_logging_organization_sink.lifecycle[id].writer_identity
      lifecycle_topic                     = google_pubsub_topic.lifecycle[id].name
      service_account_email               = google_service_account.connector[id].email
      workload_identity_audience          = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.connector[id].name}"
      workload_identity_pool              = google_iam_workload_identity_pool.connector[id].name
      workload_identity_pool_provider     = google_iam_workload_identity_pool_provider.connector[id].name
    }
  }
}

output "custom_roles" {
  description = "Names of the custom roles that the module creates, or null for a role that it does not create."
  value = {
    artifact_reader         = try(google_organization_iam_custom_role.artifact_reader[0].name, null)
    config_reader           = google_organization_iam_custom_role.config_reader.name
    function_source         = try(google_organization_iam_custom_role.function_source[0].name, null)
    vm_deployer             = try(google_organization_iam_custom_role.vm_deployer[0].name, null)
    vm_orchestrator         = try(google_organization_iam_custom_role.vm_orchestrator[0].name, null)
    vm_project_orchestrator = try(google_organization_iam_custom_role.vm_project_orchestrator[0].name, null)
  }
}

output "federation_subjects" {
  description = "AWS IAM role ARNs that each account's workload identity provider trusts, keyed by AWS account ID."
  value       = local.federation_subjects
}

output "organization_id" {
  description = "GCP organization ID."
  value       = local.org
}

output "per_account_connector_inputs" {
  description = "Values each onboarded account needs to create its connector, keyed `<aws account>-<aws region>`."
  value = {
    for k, s in local.subscriptions : k => {
      aws_account_id                  = s.aws_account_id
      aws_region                      = s.aws_region
      organization_id                 = local.org
      project_id                      = local.project
      project_number                  = local.project_number
      service_account_email           = google_service_account.connector[s.aws_account_id].email
      workload_identity_pool_provider = google_iam_workload_identity_pool_provider.connector[s.aws_account_id].name
      discovery_label                 = "aws-config-discovery=${s.discovery_label}"
      lifecycle_subscription          = google_pubsub_subscription.lifecycle[k].name
      cai_subscription                = google_pubsub_subscription.cai[k].name
      inspector_pull_subscription     = try(google_pubsub_subscription.inspector_pull[k].name, null)
    }
  }
}

output "project_id" {
  description = "GCP management project ID."
  value       = local.project
}

output "project_number" {
  description = "GCP management project number, as used in the workload identity principalSet path."
  value       = local.project_number
}

output "service_agents" {
  description = "Emails of the Google-managed service agents that the module creates or grants roles to. The OS Config agents are null without VM scanning; `pubsub` is null without `pubsub_kms_key_name`."
  value = {
    cloud_asset = google_project_service_identity.cloud_asset.email
    pubsub      = try(google_project_service_identity.pubsub[0].email, null)
    organization = {
      osconfig            = try(google_organization_service_identity.orchestrator["osconfig.googleapis.com"].email, null)
      osconfig_rollout    = local.any_inspector_vm ? "service-org-${local.org}@gcp-sa-osconfig-rollout.iam.gserviceaccount.com" : null
      progressive_rollout = try(google_organization_service_identity.orchestrator["progressiverollout.googleapis.com"].email, null)
    }
    target_projects = {
      for p in local.vm_targets : p => {
        osconfig            = google_project_service_identity.target_orchestrator["${p}:osconfig.googleapis.com"].email
        osconfig_rollout    = "service-${local.project_numbers[p]}@gcp-sa-osconfig-rollout.iam.gserviceaccount.com"
        progressive_rollout = google_project_service_identity.target_orchestrator["${p}:progressiverollout.googleapis.com"].email
      }
    }
  }
}
