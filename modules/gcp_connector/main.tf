locals {
  org     = var.organization_id
  project = var.project_id

  # The workload identity principalSet path uses the project NUMBER, not the ID.
  # It comes from the preflight project record (preflight.tf), not from a
  # google_project data source, so that a missing or inactive project stops
  # at the preflight message instead of a provider read error.
  project_number = local.project_numbers[local.project]

  ##################################################
  # Accounts
  ##################################################
  # Keyed per account and Region pair: one subscription per topic and Region.
  accounts = {
    for a in var.onboarded_accounts : "${a.aws_account_id}-${a.aws_region}" => a
  }

  account_ids = distinct([for a in var.onboarded_accounts : a.aws_account_id])

  # Per-account rollup. Federation subjects contain no Region, so a pipeline is
  # on for an account when any of its Regions enables it. VM scanning is on for
  # an account when one of its entries enables Inspector and VM scanning, and
  # target_project_ids is not empty.
  account_flags = {
    for id in local.account_ids : id => {
      issuer_url       = [for a in var.onboarded_accounts : a.issuer_url if a.aws_account_id == id][0]
      enable_inspector = anytrue([for a in var.onboarded_accounts : a.enable_inspector if a.aws_account_id == id])
      enable_inspector_vm = (
        anytrue([for a in var.onboarded_accounts : a.enable_inspector && a.enable_inspector_vm if a.aws_account_id == id])
        && length(var.target_project_ids) > 0
      )
    }
  }

  # Organization-wide gates. Custom roles, the audit configuration and the
  # service agents belong to the organization, so one account that needs them
  # creates them for all.
  any_inspector    = anytrue([for f in values(local.account_flags) : f.enable_inspector])
  any_inspector_vm = anytrue([for f in values(local.account_flags) : f.enable_inspector_vm])

  ##################################################
  # Names
  ##################################################
  # AWS Config and Amazon Inspector find these resources by name and by the
  # aws-config-discovery label. Do not change the templates.
  account_names = {
    for id in local.account_ids : id => {
      pool                 = "connector-pool-${id}"
      provider             = "connector-oidc-${id}"
      service_account_id   = "config-sa-${id}"
      lifecycle_sink       = "config-lifecycle-sink-${id}"
      lifecycle_topic      = "config-lifecycle-topic-${id}"
      feed                 = "config-cai-feed-${id}"
      feed_topic           = "config-cai-topic-${id}"
      inspector_pull_sink  = "inspector-pull-sink-${id}"
      inspector_pull_topic = "inspector-pull-topic-${id}"
    }
  }

  # The discovery label value is <account>-<region>-<management project>.
  # Inspector subscriptions follow each entry's own enable_inspector, not the
  # account rollup.
  subscriptions = {
    for k, a in local.accounts : k => {
      aws_account_id   = a.aws_account_id
      aws_region       = a.aws_region
      enable_inspector = a.enable_inspector
      discovery_label  = "${a.aws_account_id}-${a.aws_region}-${local.project}"
      lifecycle        = "config-lifecycle-sub-${a.aws_account_id}-${a.aws_region}"
      feed             = "config-cai-sub-${a.aws_account_id}-${a.aws_region}"
      inspector_pull   = "inspector-pull-sub-${a.aws_account_id}-${a.aws_region}"
    }
  }

  ##################################################
  # Federation
  ##################################################
  # Plain role ARNs, the `sub` claim of the AWS token. AWS Config federates as
  # either its customer-managed role or its service-linked role, so both are
  # always trusted. Keep this order: a tool that rechecks an existing provider
  # compares the exact ordered list.
  federation_subjects = {
    for id, f in local.account_flags : id => concat(
      [
        "arn:aws:iam::${id}:role/AWSConfigThirdPartyCloudFederationRole",
        "arn:aws:iam::${id}:role/aws-service-role/thirdparty.config.amazonaws.com/AWSServiceRoleForConfigThirdParty",
      ],
      f.enable_inspector ? [
        "arn:aws:iam::${id}:role/aws-service-role/thirdparty.inspector2.amazonaws.com/AWSServiceRoleForAmazonInspector2ThirdParty",
      ] : [],
      f.enable_inspector_vm ? [
        "arn:aws:iam::${id}:role/Inspector2SSMFederationRole-${local.org}",
      ] : [],
    )
  }

  # There are always at least two subjects, so the condition always uses `in`.
  provider_conditions = {
    for id, subs in local.federation_subjects : id =>
    "attribute.aws_role in [${join(", ", [for s in subs : "'${s}'"])}]"
  }

  # AWS Config and Inspector request the STS audience. AWS Systems Manager is
  # migrating from api://AWSTokenExchange to the same audience; retain both for
  # VM scanning until that rollout is verified in every supported Region.
  provider_audiences = {
    for id, f in local.account_flags : id => (
      f.enable_inspector_vm
      ? ["https://sts.googleapis.com", "api://AWSTokenExchange"]
      : ["https://sts.googleapis.com"]
    )
  }

  principal_prefix = {
    for id, n in local.account_names : id =>
    "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${n.pool}/attribute.aws_role"
  }

  impersonation = {
    for pair in flatten([
      for id, subs in local.federation_subjects : [
        for s in subs : { key = "${id}|${s}", account = id, subject = s }
      ]
    ]) : pair.key => pair
  }

  ##################################################
  # Organization reader roles
  ##################################################
  always_on_org_roles = [
    "roles/cloudasset.viewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/browser",
    "roles/pubsub.viewer",
    "roles/iam.securityReviewer",
  ]

  granular_org_roles = [
    "roles/artifactregistry.reader", "roles/bigquery.metadataViewer",
    "roles/cloudfunctions.viewer", "roles/compute.viewer", "roles/container.clusterViewer",
    "roles/dns.reader", "roles/eventarc.viewer", "roles/datastore.viewer",
    "roles/iam.serviceAccountViewer", "roles/logging.viewer", "roles/run.viewer",
    "roles/secretmanager.viewer", "roles/cloudsql.viewer", "roles/storage.bucketViewer",
    "roles/cloudkms.viewer", "roles/serviceusage.apiKeysViewer", "roles/monitoring.viewer",
    "roles/dataproc.viewer", "roles/dlp.reader", "roles/orgpolicy.policyViewer",
    "roles/vpcaccess.viewer", "roles/serviceusage.serviceUsageViewer",
  ]

  config_read_roles = (
    var.permission_model == "broad"
    ? concat(["roles/viewer"], local.always_on_org_roles)
    : concat(local.always_on_org_roles, local.granular_org_roles)
  )

  reader_grants = {
    for pair in setproduct(local.account_ids, local.config_read_roles) :
    "${pair[0]}|${pair[1]}" => { account = pair[0], role = pair[1] }
  }

  ##################################################
  # Management project APIs
  ##################################################
  management_apis = toset([
    "apikeys.googleapis.com", "artifactregistry.googleapis.com", "bigquery.googleapis.com",
    "cloudasset.googleapis.com", "cloudfunctions.googleapis.com", "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com", "compute.googleapis.com", "container.googleapis.com",
    "dataproc.googleapis.com", "dlp.googleapis.com", "dns.googleapis.com",
    "eventarc.googleapis.com", "firestore.googleapis.com", "iam.googleapis.com",
    "iamcredentials.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com",
    "orgpolicy.googleapis.com", "pubsub.googleapis.com", "run.googleapis.com",
    "secretmanager.googleapis.com", "sqladmin.googleapis.com", "sts.googleapis.com",
    "storage.googleapis.com", "vpcaccess.googleapis.com",
  ])
}

##################################################
# Management project APIs
##################################################
# disable_on_destroy = false: other workloads in the project can depend on them.
resource "google_project_service" "management" {
  for_each = local.management_apis

  project            = local.project
  service            = each.value
  disable_on_destroy = false

  depends_on = [terraform_data.preflight]
}

resource "google_project_service" "management_osconfig" {
  count = local.any_inspector_vm ? 1 : 0

  project            = local.project
  service            = "osconfig.googleapis.com"
  disable_on_destroy = false

  depends_on = [terraform_data.preflight]
}

##################################################
# Workload identity federation (AWS to GCP)
##################################################
resource "google_iam_workload_identity_pool" "connector" {
  for_each = local.account_names

  project                   = local.project
  workload_identity_pool_id = each.value.pool
  display_name              = "Config Connector Pool"
  disabled                  = false

  depends_on = [google_project_service.management]
}

# Accepts only a token whose issuer is the account's issuer, whose audience is
# allowed, and whose subject is one of the account's trusted roles. The
# condition and the impersonation bindings below use the same subject list.
resource "google_iam_workload_identity_pool_provider" "connector" {
  for_each = local.account_names

  project                            = local.project
  workload_identity_pool_id          = google_iam_workload_identity_pool.connector[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = each.value.provider
  display_name                       = "Config Connector OIDC"
  disabled                           = false

  attribute_mapping = {
    "google.subject"     = "assertion.sub"
    "attribute.aws_role" = "assertion.sub"
  }

  attribute_condition = local.provider_conditions[each.key]

  oidc {
    issuer_uri        = local.account_flags[each.key].issuer_url
    allowed_audiences = local.provider_audiences[each.key]
  }
}

##################################################
# Connector service account
##################################################
resource "google_service_account" "connector" {
  for_each = local.account_names

  project      = local.project
  account_id   = each.value.service_account_id
  display_name = "Config Connector SA"

  depends_on = [google_project_service.management]
}

# google_organization_iam_member, not _binding: _binding is authoritative for
# the role and would remove its other members.
resource "google_organization_iam_member" "connector_read" {
  for_each = local.reader_grants

  org_id = local.org
  role   = each.value.role
  member = "serviceAccount:${google_service_account.connector[each.value.account].email}"
}

# One binding per trusted subject.
resource "google_service_account_iam_member" "impersonation" {
  for_each = local.impersonation

  service_account_id = google_service_account.connector[each.value.account].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.principal_prefix[each.value.account]}/${each.value.subject}"

  # The attribute.aws_role mapping must exist before the principalSet is used.
  depends_on = [google_iam_workload_identity_pool_provider.connector]
}
