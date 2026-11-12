##################################################
# Amazon Inspector VM credential bridge
##################################################
# The Inspector VM scanner on a GCP VM gets AWS credentials without a key:
#
# 1. It gets a Compute Engine VM identity token for the bridge provider's
#    audience and exchanges it at Google STS in the bridge pool.
# 2. As the federated identity, it calls generateIdToken on its own project's
#    minter service account, inspector-vmscan-<account>@<project>.
# 3. It presents that Google-signed token to AWS STS for
#    Inspector2VmScannerRole-<organization>.
#
# A VM token has no organization claim; the minter token adds one. Amazon
# Inspector owns the AWS role and its trust policy, which trust the minter
# name, the account and the organization number. The Inspector VM scanner
# derives the pool, provider and minter names, so do not change them.
#
# The module owns the provider condition: it lists exactly the
# target_project_ids numbers, so an apply drops a project that only an earlier
# script run added.

locals {
  bridge_accounts = var.enable_inspector_vm_bridge ? local.inspector_vm_accounts : {}

  bridge_names = {
    for id in keys(local.bridge_accounts) : id => {
      pool      = "inspector-vm-bridge-${id}"
      provider  = "compute-engine-vm"
      minter_id = "inspector-vmscan-${id}"
    }
  }

  # The provider's own name is not known before apply, so the audience is
  # built from the management project number and the fixed names.
  bridge_audiences = {
    for id, n in local.bridge_names : id =>
    "https://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${n.pool}/providers/${n.provider}"
  }

  # shortcut: sort() is lexical, which equals numeric order only for project
  # numbers of equal length (usually 12 digits). A mixed-length list orders
  # differently from the setup script, which changes only the string, not the
  # set of projects admitted.
  bridge_project_numbers = sort(distinct([for p in local.vm_targets : local.project_numbers[p]]))

  bridge_condition_listed = "attribute.project_number in [${join(", ", formatlist("'%s'", local.bridge_project_numbers))}] && attribute.instance_id != ''"

  # Over 4096 characters (about 250 projects), any Compute Engine VM token is
  # admitted. Each minter binding still admits only its own project's VMs.
  bridge_condition = (
    length(local.bridge_condition_listed) > 4096
    ? "attribute.project_number != '' && attribute.instance_id != ''"
    : local.bridge_condition_listed
  )

  bridge_minters = {
    for pair in setproduct(tolist(local.vm_targets), keys(local.bridge_accounts)) :
    "${pair[0]}|${pair[1]}" => { project = pair[0], account = pair[1] }
  }
}

resource "google_iam_workload_identity_pool" "bridge" {
  for_each = local.bridge_names

  project                   = local.project
  workload_identity_pool_id = each.value.pool
  display_name              = "Amazon Inspector VM bridge"
  description               = "Exchanges Compute Engine VM identity tokens for Amazon Inspector VM scanning."
  disabled                  = false

  depends_on = [terraform_data.preflight, google_project_service.management]
}

# Accepts only Google-signed Compute Engine VM identity tokens from the target
# projects. No JWKS is uploaded: the issuer's published keys are used.
resource "google_iam_workload_identity_pool_provider" "bridge" {
  for_each = local.bridge_names

  project                            = local.project
  workload_identity_pool_id          = google_iam_workload_identity_pool.bridge[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = each.value.provider
  display_name                       = "Compute Engine VM tokens"
  description                        = "Admits only Compute Engine VM identity tokens for Amazon Inspector VM scanning."
  disabled                           = false

  # The project_number claim is a JSON number, so int() comes first.
  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.project_id"     = "assertion.google.compute_engine.project_id"
    "attribute.project_number" = "string(int(assertion.google.compute_engine.project_number))"
    "attribute.instance_id"    = "assertion.google.compute_engine.instance_id"
    "attribute.sa_email"       = "assertion.email"
  }

  attribute_condition = local.bridge_condition

  oidc {
    issuer_uri        = "https://accounts.google.com"
    allowed_audiences = [local.bridge_audiences[each.key]]
  }
}

# One minter per target project and VM scanning account. It gets no role and
# no key; the binding below is its only grant.
resource "google_service_account" "minter" {
  for_each = local.bridge_minters

  project      = each.value.project
  account_id   = local.bridge_names[each.value.account].minter_id
  display_name = "Amazon Inspector VM scan minter, account ${each.value.account}"
  description  = "Signs the token Amazon Inspector VM scanners in this project exchange for AWS credentials. Grant it no roles and create no keys."
  disabled     = false

  depends_on = [terraform_data.preflight, google_project_service.target_vm]
}

# Only VMs of the minter's own project can sign as that minter. Additive, so
# other members of the role stay.
resource "google_service_account_iam_member" "minter_token_creator" {
  for_each = local.bridge_minters

  service_account_id = google_service_account.minter[each.key].name
  role               = "roles/iam.serviceAccountOpenIdTokenCreator"
  member             = "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${local.bridge_names[each.value.account].pool}/attribute.project_id/${each.value.project}"

  # The attribute.project_id mapping must exist before the principalSet is used.
  depends_on = [terraform_data.preflight, google_iam_workload_identity_pool_provider.bridge]
}
