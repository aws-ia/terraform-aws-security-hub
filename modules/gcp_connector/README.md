# AWS Security Hub GCP connector

Creates the Google Cloud resources that let AWS Config and Amazon Inspector read a GCP organization for AWS Security Hub, without stored keys. AWS accounts authenticate with workload identity federation from their outbound identity federation issuer.

| Scope | Enabled by | Resources |
|-------|-----------|-----------|
| Per AWS account | always | Workload identity pool and OIDC provider, connector service account with organization reader roles, impersonation bindings, organization lifecycle log sink and topic, Cloud Asset Inventory feed and topic |
| Per AWS account and Region | always | One pull subscription on the lifecycle topic and one on the feed topic, with the `aws-config-discovery` label |
| Organization | always | `allServices` `DATA_WRITE` audit log (unless `manage_audit_config = false`), Cloud Asset service agent, management project APIs |
| Per AWS account | `enable_inspector` | Amazon Inspector federation subject, `inspectorFunctionSourceReader` custom role grant, image-pull log sink and topic |
| Per AWS account and Region | `enable_inspector` | Pull subscription on the image-pull topic |
| Organization | any `enable_inspector` | `inspectorFunctionSourceReader` custom role, Artifact Registry `DATA_READ` audit log (unless `manage_audit_config = false`) |
| Per AWS account | `enable_inspector`, `enable_inspector_vm` and `target_project_ids` | VM scanning federation subject, `OSPolicySSMOrchestrator` grant at the organization, `OSPolicySSMProjectOrchestrator` grant in the management project (with `vm_orchestrator_parent = "project"`), `OSPolicySSMTargetDeployer` grant in each target project |
| Organization and each target project | VM scanning for any account | `OSPolicySSMOrchestrator`, `OSPolicySSMTargetDeployer` and, with `vm_orchestrator_parent = "project"`, `OSPolicySSMProjectOrchestrator` custom roles, OS Config and Progressive Rollout service agents and their roles, `enable-osconfig` project metadata, VM Manager `full` feature set |
| Per AWS account and each target project | VM scanning and `enable_inspector_vm_bridge = true` (opt-in) | Amazon Inspector VM credential bridge: workload identity pool `inspector-vm-bridge-<account>` and OIDC provider `compute-engine-vm` in the management project, minter service account `inspector-vmscan-<account>` and its token creator binding in each target project, IAM and IAM Credentials APIs in each target project |
| Management project | `pubsub_kms_key_name` | Pub/Sub service agent and its `roles/cloudkms.cryptoKeyEncrypterDecrypter` grant on the key |

The connector finds its resources by name and by the `aws-config-discovery=<account>-<region>-<management project>` label, so the module uses fixed name templates such as `connector-pool-<account>` and `config-sa-<account>`.

The Cloud Asset Inventory feed sends every asset type except `osconfig.googleapis.com/*`. Security Hub does not use the OS Config asset types, and a large VM fleet can produce millions of them.

## Permissions

The `google` and `google-beta` provider identity needs:

- On the organization: Organization Administrator (`roles/resourcemanager.organizationAdmin`) for the organization IAM grants and audit configuration, Organization Role Administrator (`roles/iam.organizationRoleAdmin`) for the custom roles, Logs Configuration Writer (`roles/logging.configWriter`) for the log sinks, Cloud Asset Owner (`roles/cloudasset.owner`) for the feeds, and Folder Viewer (`roles/resourcemanager.folderViewer`) for the project ancestry check.
- Owner on the management project and on every project in `target_project_ids`.
- With `pubsub_kms_key_name`: permission to set the key's IAM policy (`cloudkms.cryptoKeys.setIamPolicy`, for example Cloud KMS Admin, `roles/cloudkms.admin`, on the key).

Configure the management project as the provider's billing project, with `user_project_override = true`, so that organization-level reads bill to it.

## Usage

```hcl
provider "google" {
  project               = "my-management-project"
  billing_project       = "my-management-project"
  user_project_override = true
}

provider "google-beta" {
  project               = "my-management-project"
  billing_project       = "my-management-project"
  user_project_override = true
}

module "gcp_connector" {
  source = "aws-ia/security-hub/aws//modules/gcp_connector"

  enable_inspector_vm_bridge = true
  organization_id            = "000000000000"
  project_id                 = "my-management-project"
  target_project_ids         = ["my-vm-project"]

  onboarded_accounts = [{
    aws_account_id   = "123456789012"
    aws_region       = "us-east-1"
    issuer_url       = "https://00000000-0000-0000-0000-000000000000.tokens.sts.global.api.aws"
    enable_inspector = true
  }]
}
```

Get an account's issuer URL with `aws iam get-outbound-web-identity-federation-info`. If outbound identity federation is not enabled, enable it with `aws iam enable-outbound-web-identity-federation`.

## Shared `onboarded_accounts` lists

Every connector module takes the same `onboarded_accounts` list, but two attributes behave differently here:

- `enable_cspm` is accepted and not read. The lifecycle sink, the Cloud Asset Inventory feed and the audit log feed AWS Config, which Amazon Inspector's GCP connector also uses to discover resources, so there are no CSPM-only resources for `false` to turn off. `azure_connector_entra` treats `enable_cspm` the same way; in `azure_connector_arm`, `enable_cspm = false` turns off the CSPM pipeline.
- `enable_inspector` defaults to `false` here and to `true` in both Azure modules. On GCP, Inspector adds organization-wide changes: the Artifact Registry `DATA_READ` audit log for the whole organization, organization custom roles and Cloud Functions source read across the organization. Set `enable_inspector` explicitly in a list that several modules share.

## VM scanning permissions

AWS Systems Manager installs the Amazon Inspector VM scanner through an OS policy orchestrator. For a connector with project targets it creates the orchestrator in the management project; for an ORGANIZATION-scope connector it creates it under the organization, and the orchestrator then reaches every VM with an active OS Config agent in the organization. Creating an orchestrator needs `osconfig.policyOrchestrators.*` on its parent, and the orchestrator writes the OS policy assignments through the OS Config rollout service agent. So the VM permissions are split:

- `OSPolicySSMOrchestrator`, granted at the organization: read-only compute, inventory, OS policy, asset, project and service usage permissions, plus the `osconfig.policyOrchestrators.*` permissions when `vm_orchestrator_parent = "organization"`.
- `OSPolicySSMProjectOrchestrator`, only with `vm_orchestrator_parent = "project"`, granted only in the management project: the `osconfig.policyOrchestrators.*` permissions.
- `OSPolicySSMTargetDeployer`, granted only in each `target_project_ids` project: `compute.instances.setMetadata`, `compute.instances.setLabels`, `iam.serviceAccounts.actAs` and the OS policy assignment writes. No organization grant can set VM metadata or act as a VM's service account.

This module sets `enable-osconfig` and VM Manager only in `target_project_ids`.

The connector workload identity provider allows only `https://sts.googleapis.com`, which AWS Config, Inspector and Systems Manager request.

Choose `vm_orchestrator_parent` by the connector's scope:

| Connector scope | Orchestrator parent | `vm_orchestrator_parent` |
|---|---|---|
| ORGANIZATION, no project targets | The organization | `organization` (required) |
| Project targets | The management project | `project` or `organization` |

`organization` (the default) works for every scope. `project` keeps orchestrator writes out of the organization, but if the connector later changes to ORGANIZATION scope with no project targets, Systems Manager cannot create the orchestrator until you set `organization` and apply.

## VM credential bridge

The Amazon Inspector VM scanner on a GCP VM gets AWS credentials through the bridge, with no stored key:

1. The scanner gets a Compute Engine VM identity token for the audience `https://iam.googleapis.com/projects/<management project number>/locations/global/workloadIdentityPools/inspector-vm-bridge-<account>/providers/compute-engine-vm` and exchanges it at Google STS in the bridge pool.
2. As that federated identity, it calls `generateIdToken` on its own project's minter, `inspector-vmscan-<account>@<project>.iam.gserviceaccount.com`. A VM token has no organization claim; the minter token adds one.
3. It presents the minter token to AWS STS for `Inspector2VmScannerRole-<organization>`.

For each account with VM scanning, the module creates:

- In the management project: the pool `inspector-vm-bridge-<account>` and the provider `compute-engine-vm`. The provider trusts only `https://accounts.google.com` with exactly the audience above, maps `project_id`, `project_number`, `instance_id` and `sa_email` from the VM token, and admits only VM tokens from the `target_project_ids` projects (`attribute.project_number in [...] && attribute.instance_id != ''`). Over 4096 characters, about 250 projects, the condition admits any Compute Engine VM token instead; each minter binding still admits only its own project's VMs.
- In each target project: the minter service account `inspector-vmscan-<account>` with no roles and no keys, and one `roles/iam.serviceAccountOpenIdTokenCreator` binding on it for `principalSet://iam.googleapis.com/projects/<management project number>/locations/global/workloadIdentityPools/inspector-vm-bridge-<account>/attribute.project_id/<project>`, with no condition.

The scanner must request a Compute Engine identity token with `format=full`; the standard token format omits the project and instance claims used by the provider mapping.

The minter binding is deliberately project-wide. Any Compute Engine VM identity in a listed target project can mint as that project's minter. The AWS role still pins the minter name, AWS account and GCP organization. Restrict who can create VMs in target projects, and treat permission to add or update providers in the bridge pool as bridge trust administration.

The Inspector VM scanner derives these names, so the module uses fixed names. Amazon Inspector owns the AWS side: the role `Inspector2VmScannerRole-<organization>` and its trust statement `AllowBridgeMinter`, which trusts `accounts.google.com` tokens with `oaud` `api://AWSInspector`, a minter email `inspector-vmscan-<account>@*.iam.gserviceaccount.com` and the organization number. This module creates nothing in AWS.

Terraform owns the provider condition exactly. Another onboarding workflow may add project numbers to the condition across runs; this module lists only `target_project_ids`, so an apply removes a project that only the earlier workflow set up, and that project's VMs then cannot get credentials. Add every project to `target_project_ids` before importing or replacing an existing bridge.

`enable_inspector_vm_bridge` defaults to `false` so upgrading an existing deployment cannot collide with a bridge created by another onboarding workflow. For a new deployment, set it to `true`. For an existing bridge, import the fixed resources before enabling it:

```bash
terraform import 'module.gcp_connector.google_iam_workload_identity_pool.bridge["<account>"]' \
  'projects/<management-project>/locations/global/workloadIdentityPools/inspector-vm-bridge-<account>'
terraform import 'module.gcp_connector.google_iam_workload_identity_pool_provider.bridge["<account>"]' \
  'projects/<management-project>/locations/global/workloadIdentityPools/inspector-vm-bridge-<account>/providers/compute-engine-vm'
terraform import 'module.gcp_connector.google_service_account.minter["<target-project>|<account>"]' \
  'projects/<target-project>/serviceAccounts/inspector-vmscan-<account>@<target-project>.iam.gserviceaccount.com'
```

Repeat the minter import for every target project. The additive token-creator binding needs no import. Verify the imported provider condition lists every `target_project_ids` project before applying, because Terraform owns that condition exactly.

Setting the variable back to `false` destroys a bridge already managed by this state. A destroyed pool stays soft-deleted for about 30 days and keeps its ID reserved. A deleted minter is also retained temporarily and must be undeleted by its numeric unique ID before the same email can be managed again.

The module grants no other binding on a minter and does not check for user-managed keys. Do not create keys for a minter.

## Encryption

The lifecycle, Cloud Asset Inventory and image-pull topics use Google-managed encryption. Set `pubsub_kms_key_name` to use a Cloud KMS key instead. The module then grants the management project's Pub/Sub service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key before it creates the topics.

## Checks before any write

The plan stops before it creates anything when:

- The management project or a VM target project does not exist, is not `ACTIVE`, or is not in `organization_id` through any folder depth. The module reads the project number from the same project list, so a missing project stops with this check's message, not a provider read error. When the caller cannot read a parent folder, the plan stops with the provider's folder read error.
- An organization audit exemption (`exemptedMembers`) suppresses an audit event that the connector needs. The module does not remove an existing exemption.
- `manage_audit_config` is `false` and the organization does not enable a required audit log type (`allServices` `DATA_WRITE`, and with Inspector `artifactregistry.googleapis.com` `DATA_READ`).

## Audit configuration

`google_organization_iam_audit_config` replaces the whole audit configuration of the service it names. The module reads the organization IAM policy during plan and keeps the log types and exemptions that are already set on `allServices` and, with Inspector, on `artifactregistry.googleapis.com`. Folder and project audit configurations are not changed.

Set `manage_audit_config = false` when another configuration owns the organization audit configuration. The module then creates no audit configuration, checks that the required log types are already on, and leaves the audit configuration unchanged on destroy. In an existing deployment, run `terraform state rm` on the two audit configuration resources before you change it to `false`, or the next apply removes them (see Destroying).

## VM scanning and gcloud

The module creates the organization and target project OS Config and Progressive Rollout service identities with `google_organization_service_identity` and `google_project_service_identity`. Generating the OS Config identity also creates the `gcp-sa-osconfig-rollout` agent. One step has no provider resource: the VM Manager `full` feature set. The module runs `gcloud` for it with `local-exec`, so an apply with `target_project_ids` needs the `gcloud` CLI on `PATH`. `gcloud` uses the `google` provider's access token, so it acts as the same identity as Terraform. Terraform suppresses the command output because the token is sensitive; if a command fails, run it by hand to see the error. The token expires after about one hour, so apply a saved plan within that time.

## Secrets in Terraform state

With `target_project_ids`, the `google_client_config` data source stores the provider's short-lived access token in state. Store the state in an encrypted remote backend with access limited to the people and pipelines that apply this module.

## Existing deployments

This module creates new resources. If a resource with the same name already exists, for example from an earlier setup of the connector, the apply fails on that resource. To manage existing resources, add `import` blocks in your root module. An imported Cloud Asset Inventory feed has `billing_project`, `org_id` and `feed_id` empty in state, so the module ignores changes to those three attributes instead of replacing the feed.

## Destroying

Destroying the module removes everything it created, including resources that other workloads in the organization can share:

- The `allServices` and `artifactregistry.googleapis.com` audit configurations, including log types and exemptions that existed before. To keep them, set `manage_audit_config = false` before the first apply. In an existing deployment, first run `terraform state rm` on `google_organization_iam_audit_config.all_services_write` and `google_organization_iam_audit_config.artifactregistry_read`; changing the input alone removes them on the next apply.
- The `inspectorFunctionSourceReader`, `OSPolicySSMOrchestrator` and `OSPolicySSMTargetDeployer` custom roles. A deleted custom role keeps its role ID reserved, so creating it again fails until you undelete the role or GCP completes the deletion.
- The `enable-osconfig` metadata item, which turns off the OS Config agent for every VM in the target projects.
- The VM credential bridge pool, provider, minter service accounts and bindings, which stops VM scanning credentials.

A destroyed workload identity pool, connector or bridge, stays soft-deleted for 30 days and blocks a new pool with the same name until you undelete it. Service identities cannot be destroyed, so they stay. The VM Manager feature set that `gcloud` sets is not changed back.

### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.50 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 7.27 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.50 |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | >= 7.27 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

### Modules

No modules.

### Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_organization_service_identity.orchestrator](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_organization_service_identity) | resource |
| [google-beta_google_project_service_identity.cloud_asset](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google-beta_google_project_service_identity.pubsub](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google-beta_google_project_service_identity.target_orchestrator](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_cloud_asset_organization_feed.cai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_asset_organization_feed) | resource |
| [google_compute_project_metadata_item.target_enable_osconfig](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_project_metadata_item) | resource |
| [google_iam_workload_identity_pool.bridge](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.bridge](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_iam_workload_identity_pool_provider.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_kms_crypto_key_iam_member.pubsub_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_logging_organization_sink.inspector_pull](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_logging_organization_sink.lifecycle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_organization_iam_audit_config.all_services_write](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_audit_config) | resource |
| [google_organization_iam_audit_config.artifactregistry_read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_audit_config) | resource |
| [google_organization_iam_custom_role.function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_custom_role.vm_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_custom_role.vm_orchestrator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_custom_role.vm_project_orchestrator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_member.connector_read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.inspector_function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.org_orchestrator_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.vm_orchestrator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_project_iam_member.cloud_asset_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.target_orchestrator_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.vm_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.vm_project_orchestrator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.management](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.management_osconfig](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.target_vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_pubsub_subscription.cai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription.inspector_pull](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription.lifecycle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription_iam_member.cai_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription_iam_member) | resource |
| [google_pubsub_subscription_iam_member.inspector_pull_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription_iam_member) | resource |
| [google_pubsub_subscription_iam_member.lifecycle_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription_iam_member) | resource |
| [google_pubsub_topic.cai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic.inspector_pull](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic.lifecycle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic_iam_member.cai_agent_publisher](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_pubsub_topic_iam_member.inspector_pull_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_pubsub_topic_iam_member.lifecycle_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_service_account.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.minter](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.impersonation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.minter_token_creator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [terraform_data.preflight](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.target_vm_manager_full](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [google_client_config.current](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |
| [google_folder.parent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/folder) | data source |
| [google_organization_iam_policy.organization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/organization_iam_policy) | data source |
| [google_projects.checked](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/projects) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from this GCP organization.<br/>`aws_account_id`      - 12-digit AWS account ID. Names the workload identity pool and provider, the service account, the log sinks, the Cloud Asset Inventory feed and the topics.<br/>`aws_region`          - AWS Region of the connector, for example `us-east-1`. Names the Pub/Sub subscriptions and forms their discovery label.<br/>`issuer_url`          - The account's outbound identity federation issuer URL, `https://<id>.tokens.sts.global.api.aws`.<br/>`enable_cspm`         - Enable the CSPM pipeline. Defaults to `true`. The shared AWS Config resources are always created, so this module does not read it; accepted so every connector module takes the same list.<br/>`enable_inspector`    - Enable Amazon Inspector for this account and Region. Defaults to `false`. Adds Inspector federation, Cloud Functions source access, the image-pull log route and the Artifact Registry read audit log.<br/>`enable_inspector_vm` - With `enable_inspector` and a nonempty `target_project_ids`, trust this account's VM scanning role, grant it the OS policy orchestrator role at the organization and the VM deployer role in each target project. Defaults to `true`. Set `false` for an Inspector account that must not get VM access.<br/>An account can appear once per Region. Per-account resources are created once per account; Inspector is on for an account when any of its Regions enables it. | <pre>list(object({<br/>    aws_account_id      = string<br/>    aws_region          = string<br/>    issuer_url          = string<br/>    enable_cspm         = optional(bool, true)<br/>    enable_inspector    = optional(bool, false)<br/>    enable_inspector_vm = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Numeric ID of the GCP organization to onboard. The log sinks, Cloud Asset Inventory feeds, reader roles, custom roles and audit configuration are created at this organization. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID of the GCP management project. It holds the service accounts, workload identity pools, topics and subscriptions, and must be in `organization_id`. Configure it as the provider's billing project. | `string` | n/a | yes |
| <a name="input_enable_inspector_vm_bridge"></a> [enable\_inspector\_vm\_bridge](#input\_enable\_inspector\_vm\_bridge) | Create the Amazon Inspector VM credential bridge for every account with VM scanning: a workload identity pool `inspector-vm-bridge-<account>` with the OIDC provider `compute-engine-vm` in the management project, and a minter service account `inspector-vmscan-<account>` in each target project. The Inspector VM scanner uses it to get AWS credentials. The module owns the provider condition: it admits exactly the `target_project_ids` projects. This is opt-in so upgrading an existing deployment cannot collide with a bridge created by another onboarding workflow. Import every existing bridge resource before setting this to true. Setting it back to false destroys the bridge, and VM scanning then cannot get AWS credentials. | `bool` | `false` | no |
| <a name="input_manage_audit_config"></a> [manage\_audit\_config](#input\_manage\_audit\_config) | Create and own the organization audit configuration that the connector needs: `allServices` `DATA_WRITE` and, with Inspector, `artifactregistry.googleapis.com` `DATA_READ`. Set `false` when another configuration owns the organization audit configuration. The module then creates no audit configuration, the plan stops when a required log type is not enabled, and destroy leaves the audit configuration unchanged. In an existing deployment, run `terraform state rm` on the two `google_organization_iam_audit_config` resources before you change this to `false`, or the next apply removes them. | `bool` | `true` | no |
| <a name="input_permission_model"></a> [permission\_model](#input\_permission\_model) | Read access of the connector service accounts at the organization. `broad` grants `roles/viewer` and the always-on reader roles. `granular` grants the always-on reader roles and one viewer role per supported service. | `string` | `"broad"` | no |
| <a name="input_pubsub_kms_key_name"></a> [pubsub\_kms\_key\_name](#input\_pubsub\_kms\_key\_name) | Optional Cloud KMS key for the lifecycle, Cloud Asset Inventory and image-pull topics, as `projects/<project>/locations/<location>/keyRings/<key ring>/cryptoKeys/<key>`. When set, the module grants the management project's Pub/Sub service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key. When `null`, the topics use Google-managed encryption. | `string` | `null` | no |
| <a name="input_target_project_ids"></a> [target\_project\_ids](#input\_target\_project\_ids) | Projects whose Compute Engine VMs Amazon Inspector scans. A nonempty list sets up VM scanning for every account that enables Inspector and `enable_inspector_vm`: VM scanning federation, the OS policy orchestrator role at the organization, the VM deployer role in each target project, the OS Config and Progressive Rollout service agents, and VM Manager in each project. The VM deployer role, which can set VM metadata and act as the VM service account, is granted only in these projects. Leave empty to skip VM scanning. | `list(string)` | `[]` | no |
| <a name="input_vm_orchestrator_parent"></a> [vm\_orchestrator\_parent](#input\_vm\_orchestrator\_parent) | Where the connector service account gets the OS policy orchestrator permissions (`osconfig.policyOrchestrators.*`) for VM scanning. AWS Systems Manager creates the scanner's orchestrator under the organization for an ORGANIZATION-scope connector with no project targets, and in the management (workload identity pool) project for a connector with project targets. `organization` grants them at the organization and works for both. `project` grants them only in the management project; use it only for project-targeted connectors. If the connector later changes to ORGANIZATION scope, orchestrator creation fails until this is `organization`. The read-only VM permissions stay at the organization, and the VM write permissions stay in `target_project_ids`, for both values. | `string` | `"organization"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_accounts"></a> [accounts](#output\_accounts) | Per-account resources, keyed by AWS account ID. `workload_identity_audience` is the exact audience for the token exchange. The sink writer identities are the principals that publish to the topics. |
| <a name="output_custom_roles"></a> [custom\_roles](#output\_custom\_roles) | Names of the custom roles that the module creates, or null for a role that it does not create. |
| <a name="output_federation_subjects"></a> [federation\_subjects](#output\_federation\_subjects) | AWS IAM role ARNs that each account's workload identity provider trusts, keyed by AWS account ID. |
| <a name="output_inspector_vm_bridge"></a> [inspector\_vm\_bridge](#output\_inspector\_vm\_bridge) | Amazon Inspector VM credential bridge of each account with VM scanning, keyed by AWS account ID: the workload identity pool and provider, the exact audience of the VM identity token, whether the provider uses the any-VM fallback condition, and the minter service account email per target project. Empty when no account has VM scanning or `enable_inspector_vm_bridge` is false. |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | GCP organization ID. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Values each onboarded account needs to create its connector, keyed `<aws account>-<aws region>`. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | GCP management project ID. |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | GCP management project number, as used in the workload identity principalSet path. |
| <a name="output_service_agents"></a> [service\_agents](#output\_service\_agents) | Emails of the Google-managed service agents that the module creates or grants roles to. The OS Config agents are null without VM scanning; `pubsub` is null without `pubsub_kms_key_name`. |
