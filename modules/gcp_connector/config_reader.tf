##################################################
# Connector read access
##################################################
# Each connector service account reads the organization through one
# organization custom role with explicit read permissions for the
# resource types that Security Hub records, plus four
# predefined roles. The custom role does not grant Cloud Storage object bytes,
# BigQuery table rows or Secret Manager secret values. Some of its permissions
# return resource configuration that the resource owner writes, such as
# instance metadata and service environment variables.

locals {
  # Keep this list sorted. IAM checks the workload identity pool, provider and
  # OAuth client reads on the iam.googleapis.com/ names, so both forms are
  # listed.
  config_reader_permissions = [
    "accesscontextmanager.policies.get",
    "accesscontextmanager.policies.getIamPolicy",
    "accesscontextmanager.policies.list",
    "accesscontextmanager.servicePerimeters.get",
    "accesscontextmanager.servicePerimeters.list",
    "apikeys.keys.get",
    "apikeys.keys.list",
    "appengine.services.get",
    "appengine.services.list",
    "appengine.versions.get",
    "appengine.versions.list",
    "artifactregistry.dockerimages.get",
    "artifactregistry.dockerimages.list",
    "artifactregistry.packages.get",
    "artifactregistry.packages.list",
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.getIamPolicy",
    "artifactregistry.repositories.list",
    "artifactregistry.versions.get",
    "artifactregistry.versions.list",
    "bigquery.datasets.get",
    "bigquery.tables.get",
    "bigquery.tables.getIamPolicy",
    "bigquery.tables.list",
    "cloudasset.assets.searchAllResources",
    "cloudfunctions.functions.get",
    "cloudfunctions.functions.getIamPolicy",
    "cloudfunctions.functions.list",
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.getIamPolicy",
    "cloudkms.cryptoKeys.list",
    "cloudkms.keyRings.get",
    "cloudkms.keyRings.getIamPolicy",
    "cloudkms.keyRings.list",
    "cloudsql.backupRuns.get",
    "cloudsql.backupRuns.list",
    "cloudsql.databases.get",
    "cloudsql.databases.list",
    "cloudsql.instances.get",
    "cloudsql.instances.list",
    "cloudsql.sslCerts.get",
    "cloudsql.sslCerts.list",
    "cloudsql.users.get",
    "cloudsql.users.list",
    "compute.addresses.get",
    "compute.addresses.list",
    "compute.backendServices.get",
    "compute.backendServices.getIamPolicy",
    "compute.backendServices.list",
    "compute.disks.get",
    "compute.disks.getIamPolicy",
    "compute.disks.list",
    "compute.firewalls.get",
    "compute.firewalls.list",
    "compute.forwardingRules.get",
    "compute.forwardingRules.list",
    "compute.globalAddresses.get",
    "compute.globalAddresses.list",
    "compute.globalForwardingRules.get",
    "compute.globalForwardingRules.list",
    "compute.globalNetworkEndpointGroups.get",
    "compute.globalNetworkEndpointGroups.list",
    "compute.instanceGroupManagers.get",
    "compute.instanceGroupManagers.list",
    "compute.instanceGroups.get",
    "compute.instanceGroups.list",
    "compute.instances.get",
    "compute.instances.getIamPolicy",
    "compute.instances.list",
    "compute.networkEndpointGroups.get",
    "compute.networkEndpointGroups.list",
    "compute.networks.get",
    "compute.networks.list",
    "compute.projects.get",
    "compute.regionBackendServices.get",
    "compute.regionBackendServices.getIamPolicy",
    "compute.regionBackendServices.list",
    "compute.regionNetworkEndpointGroups.get",
    "compute.regionNetworkEndpointGroups.list",
    "compute.regionSecurityPolicies.get",
    "compute.regionSecurityPolicies.list",
    "compute.regionSslPolicies.get",
    "compute.regionSslPolicies.list",
    "compute.regionTargetHttpProxies.get",
    "compute.regionTargetHttpProxies.list",
    "compute.regionTargetHttpsProxies.get",
    "compute.regionTargetHttpsProxies.list",
    "compute.regionUrlMaps.get",
    "compute.regionUrlMaps.list",
    "compute.securityPolicies.get",
    "compute.securityPolicies.list",
    "compute.sslPolicies.get",
    "compute.sslPolicies.list",
    "compute.subnetworks.get",
    "compute.subnetworks.getIamPolicy",
    "compute.subnetworks.list",
    "compute.targetHttpProxies.get",
    "compute.targetHttpProxies.list",
    "compute.targetHttpsProxies.get",
    "compute.targetHttpsProxies.list",
    "compute.targetPools.get",
    "compute.targetPools.list",
    "compute.targetSslProxies.get",
    "compute.targetSslProxies.list",
    "compute.urlMaps.get",
    "compute.urlMaps.list",
    "container.clusters.get",
    "container.clusters.list",
    "dataproc.clusters.get",
    "dataproc.clusters.getIamPolicy",
    "dataproc.clusters.list",
    "datastore.databases.get",
    "datastore.databases.getMetadata",
    "datastore.databases.list",
    "datastore.indexes.get",
    "datastore.indexes.list",
    "dlp.jobTriggers.get",
    "dlp.jobTriggers.list",
    "dns.managedZones.get",
    "dns.managedZones.getIamPolicy",
    "dns.managedZones.list",
    "dns.policies.get",
    "dns.policies.list",
    "eventarc.channels.get",
    "eventarc.channels.getIamPolicy",
    "eventarc.channels.list",
    "eventarc.triggers.get",
    "eventarc.triggers.getIamPolicy",
    "eventarc.triggers.list",
    "iam.denypolicies.get",
    "iam.denypolicies.list",
    "iam.googleapis.com/oauthClients.get",
    "iam.googleapis.com/oauthClients.list",
    "iam.googleapis.com/workloadIdentityPoolProviders.get",
    "iam.googleapis.com/workloadIdentityPoolProviders.list",
    "iam.googleapis.com/workloadIdentityPools.get",
    "iam.googleapis.com/workloadIdentityPools.getIamPolicy",
    "iam.googleapis.com/workloadIdentityPools.list",
    "iam.oauthClients.get",
    "iam.oauthClients.list",
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccountKeys.get",
    "iam.serviceAccountKeys.list",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "iam.workloadIdentityPoolProviders.get",
    "iam.workloadIdentityPoolProviders.list",
    "iam.workloadIdentityPools.get",
    "iam.workloadIdentityPools.getIamPolicy",
    "iam.workloadIdentityPools.list",
    "logging.logMetrics.get",
    "logging.logMetrics.list",
    "logging.sinks.get",
    "logging.sinks.list",
    "monitoring.alertPolicies.get",
    "monitoring.alertPolicies.list",
    "monitoring.timeSeries.list",
    "orgpolicy.constraints.list",
    "orgpolicy.customConstraints.get",
    "orgpolicy.customConstraints.list",
    "orgpolicy.policies.list",
    "orgpolicy.policy.get",
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.getIamPolicy",
    "pubsub.subscriptions.list",
    "pubsub.topics.get",
    "pubsub.topics.getIamPolicy",
    "pubsub.topics.list",
    "resourcemanager.folders.get",
    "resourcemanager.folders.getIamPolicy",
    "resourcemanager.hierarchyNodes.listEffectiveTags",
    "resourcemanager.hierarchyNodes.listTagBindings",
    "resourcemanager.organizations.get",
    "resourcemanager.organizations.getIamPolicy",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.tagKeys.get",
    "resourcemanager.tagKeys.getIamPolicy",
    "resourcemanager.tagKeys.list",
    "resourcemanager.tagValues.get",
    "resourcemanager.tagValues.getIamPolicy",
    "resourcemanager.tagValues.list",
    "run.executions.get",
    "run.executions.list",
    "run.jobs.get",
    "run.jobs.getIamPolicy",
    "run.jobs.list",
    "run.revisions.get",
    "run.revisions.list",
    "run.services.get",
    "run.services.getIamPolicy",
    "run.services.list",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.list",
    "secretmanager.versions.get",
    "secretmanager.versions.list",
    "serviceusage.services.get",
    "serviceusage.services.list",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
    "vpcaccess.connectors.get",
    "vpcaccess.connectors.list",
  ]

  # Cloud Asset Inventory, resource hierarchy, Pub/Sub metadata and service
  # usage. Service Usage Consumer also holds serviceusage.services.use, which
  # bills API usage to a project, so it is not a read-only role.
  always_on_org_roles = [
    "roles/cloudasset.viewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/browser",
    "roles/pubsub.viewer",
  ]

  # Keys are known at plan; the custom role's name is not.
  reader_grants = merge(
    {
      for id in local.account_ids : "${id}|${var.config_reader_role_id}" => {
        account = id
        role    = google_organization_iam_custom_role.config_reader.name
      }
    },
    {
      for pair in setproduct(local.account_ids, local.always_on_org_roles) :
      "${pair[0]}|${pair[1]}" => { account = pair[0], role = pair[1] }
    },
  )
}

resource "google_organization_iam_custom_role" "config_reader" {
  org_id      = local.org
  role_id     = var.config_reader_role_id
  title       = "Security Hub Config Reader"
  description = "Read-only resource-configuration access for AWS Security Hub. Excludes Cloud Storage object bytes, BigQuery table rows and Secret Manager secret values. Resource configuration, such as instance metadata and service environment variables, is readable."
  permissions = local.config_reader_permissions
  stage       = "GA"

  depends_on = [terraform_data.preflight]
}

# google_organization_iam_member, not _binding: _binding is authoritative for
# the role and would remove its other members.
resource "google_organization_iam_member" "connector_read" {
  for_each = local.reader_grants

  org_id = local.org
  role   = each.value.role
  member = "serviceAccount:${google_service_account.connector[each.value.account].email}"
}
