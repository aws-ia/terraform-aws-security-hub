##################################################
# AWS Config sources
##################################################
# Per AWS account: one organization lifecycle log sink and one Cloud Asset
# Inventory feed, each with a topic in the management project. Per account and
# Region: one pull subscription on each topic.

locals {
  lifecycle_filter = trimspace(<<-EOT
    (LOG_ID("cloudaudit.googleapis.com/activity") AND NOT protoPayload.methodName:"io.k8s.coordination.v1.leases.") OR (LOG_ID("cloudaudit.googleapis.com/data_access") AND NOT (protoPayload.methodName:"Docker-Get" OR protoPayload.methodName:"Docker-Head" OR protoPayload.methodName:"Docker-ServeBlob" OR protoPayload.methodName:"Docker-ListReferrers" OR protoPayload.methodName:"Docker-GetReferrers" OR protoPayload.methodName:"GenerateAccessToken"))
  EOT
  )

  # All asset types except osconfig.googleapis.com/*. OSPolicyAssignmentReport
  # and the other OS Config types are not used by Security Hub, and in a large
  # VM fleet they can produce millions of messages that back up every feed
  # subscription. The condition drops them at the source.
  cai_feed_condition = "!temporal_asset.asset.asset_type.startsWith(\"osconfig.googleapis.com/\")"
}

##################################################
# Lifecycle log sink
##################################################
resource "google_pubsub_topic" "lifecycle" {
  for_each = local.account_names

  project = local.project
  name    = each.value.lifecycle_topic

  depends_on = [google_project_service.management]
}

resource "google_pubsub_subscription" "lifecycle" {
  for_each = local.subscriptions

  project = local.project
  name    = each.value.lifecycle
  topic   = google_pubsub_topic.lifecycle[each.value.aws_account_id].id

  # The connector finds its subscription by this label.
  labels = {
    "aws-config-discovery" = each.value.discovery_label
  }

  # An empty ttl turns off the 31-day expiry of an inactive subscription.
  expiration_policy {
    ttl = ""
  }
}

# Aggregated organization sink that includes every folder and project.
resource "google_logging_organization_sink" "lifecycle" {
  for_each = local.account_names

  name             = each.value.lifecycle_sink
  org_id           = local.org
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.lifecycle[each.key].id}"
  filter           = local.lifecycle_filter
}

resource "google_pubsub_topic_iam_member" "lifecycle_writer" {
  for_each = local.account_names

  project = local.project
  topic   = google_pubsub_topic.lifecycle[each.key].name
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.lifecycle[each.key].writer_identity
}

# Granted on the subscription, not the project.
resource "google_pubsub_subscription_iam_member" "lifecycle_subscriber" {
  for_each = local.subscriptions

  project      = local.project
  subscription = google_pubsub_subscription.lifecycle[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.connector[each.value.aws_account_id].email}"
}

##################################################
# Cloud Asset Inventory feed
##################################################
resource "google_pubsub_topic" "cai" {
  for_each = local.account_names

  project = local.project
  name    = each.value.feed_topic

  depends_on = [google_project_service.management]
}

resource "google_pubsub_subscription" "cai" {
  for_each = local.subscriptions

  project = local.project
  name    = each.value.feed
  topic   = google_pubsub_topic.cai[each.value.aws_account_id].id

  labels = {
    "aws-config-discovery" = each.value.discovery_label
  }

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription_iam_member" "cai_subscriber" {
  for_each = local.subscriptions

  project      = local.project
  subscription = google_pubsub_subscription.cai[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.connector[each.value.aws_account_id].email}"
}

# Cloud Asset service agent of the management project. Every feed publishes as
# this agent.
resource "google_project_service_identity" "cloud_asset" {
  provider = google-beta

  project = local.project
  service = "cloudasset.googleapis.com"

  depends_on = [google_project_service.management]
}

resource "google_project_iam_member" "cloud_asset_agent" {
  project = local.project
  role    = "roles/cloudasset.serviceAgent"
  member  = "serviceAccount:${google_project_service_identity.cloud_asset.email}"
}

# The agent must be able to publish before the feed exists, or the first
# messages are lost.
resource "google_pubsub_topic_iam_member" "cai_agent_publisher" {
  for_each = local.account_names

  project = local.project
  topic   = google_pubsub_topic.cai[each.key].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_project_service_identity.cloud_asset.email}"
}

resource "google_cloud_asset_organization_feed" "cai" {
  for_each = local.account_names

  billing_project = local.project
  org_id          = local.org
  feed_id         = each.value.feed
  content_type    = "RESOURCE"
  asset_types     = [".*"]

  condition {
    title       = "exclude-osconfig"
    description = "Drop osconfig.googleapis.com/* asset types; Security Hub does not consume them."
    expression  = local.cai_feed_condition
  }

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.cai[each.key].id
    }
  }

  # An imported feed has billing_project, org_id and feed_id null in state, and
  # a change to any of them replaces the feed and interrupts the asset stream.
  # The for_each key and the module inputs fix all three: a change to
  # organization_id or project_id renames every other resource too.
  lifecycle {
    ignore_changes = [billing_project, org_id, feed_id]
  }

  depends_on = [
    google_pubsub_topic_iam_member.cai_agent_publisher,
    google_project_iam_member.cloud_asset_agent,
  ]
}
