output "organization_id" {
  description = "GCP organization ID."
  value       = local.org
}

output "project_id" {
  description = "GCP management project ID."
  value       = local.project
}

output "project_number" {
  description = "GCP management project number, as used in the workload identity principalSet path."
  value       = local.project_number
}

output "accounts" {
  description = "Per-account resources, keyed by AWS account ID."
  value = {
    for id, n in local.account_names : id => {
      service_account_email           = google_service_account.connector[id].email
      workload_identity_pool          = google_iam_workload_identity_pool.connector[id].name
      workload_identity_pool_provider = google_iam_workload_identity_pool_provider.connector[id].name
      lifecycle_topic                 = google_pubsub_topic.lifecycle[id].name
      cai_feed                        = google_cloud_asset_organization_feed.cai[id].feed_id
      cai_topic                       = google_pubsub_topic.cai[id].name
      inspector_pull_topic            = try(google_pubsub_topic.inspector_pull[id].name, null)
    }
  }
}

output "federation_subjects" {
  description = "AWS IAM role ARNs that each account's workload identity provider trusts, keyed by AWS account ID."
  value       = local.federation_subjects
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
