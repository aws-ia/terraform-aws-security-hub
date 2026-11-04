# AWS Security Hub GCP connector

Creates the Google Cloud resources that let AWS Config and Amazon Inspector read a GCP organization for AWS Security Hub, without stored keys. AWS accounts authenticate with workload identity federation from their outbound identity federation issuer.

| Scope | Enabled by | Resources |
|-------|-----------|-----------|
| Per AWS account | always | Workload identity pool and OIDC provider, connector service account with organization reader roles, impersonation bindings, organization lifecycle log sink and topic, Cloud Asset Inventory feed and topic |
| Per AWS account and Region | always | One pull subscription on the lifecycle topic and one on the feed topic, with the `aws-config-discovery` label |
| Organization | always | `allServices` `DATA_WRITE` audit log, Cloud Asset service agent, management project APIs |
| Per AWS account | `enable_inspector` | Amazon Inspector federation subject, `inspectorFunctionSourceReader` custom role grant, image-pull log sink and topic |
| Per AWS account and Region | `enable_inspector` | Pull subscription on the image-pull topic |
| Organization | any `enable_inspector` | `inspectorFunctionSourceReader` custom role, Artifact Registry `DATA_READ` audit log |
| Per AWS account | `enable_inspector`, `enable_inspector_vm` and `target_project_ids` | VM scanning federation subject and audience, `OSPolicySSMDeployer` custom role grant |
| Organization and each target project | VM scanning for any account | `OSPolicySSMDeployer` custom role, OS Config and Progressive Rollout service agents and their roles, `enable-osconfig` project metadata, VM Manager `full` feature set |

The connector finds its resources by name and by the `aws-config-discovery=<account>-<region>-<management project>` label, so the module uses fixed name templates such as `connector-pool-<account>` and `config-sa-<account>`.

The Cloud Asset Inventory feed sends every asset type except `osconfig.googleapis.com/*`. Security Hub does not use the OS Config asset types, and a large VM fleet can produce millions of them.

## Permissions

The `google` and `google-beta` provider identity needs:

- On the organization: Organization Administrator (`roles/resourcemanager.organizationAdmin`) for the organization IAM grants and audit configuration, Organization Role Administrator (`roles/iam.organizationRoleAdmin`) for the custom roles, Logs Configuration Writer (`roles/logging.configWriter`) for the log sinks, Cloud Asset Owner (`roles/cloudasset.owner`) for the feeds, and Folder Viewer (`roles/resourcemanager.folderViewer`) for the project ancestry check.
- Owner on the management project and on every project in `target_project_ids`.

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

  organization_id = "000000000000"
  project_id      = "my-management-project"

  onboarded_accounts = [{
    aws_account_id   = "123456789012"
    aws_region       = "us-east-1"
    issuer_url       = "https://00000000-0000-0000-0000-000000000000.tokens.sts.global.api.aws"
    enable_inspector = true
  }]
}
```

Get an account's issuer URL with `aws iam get-outbound-web-identity-federation-info`. If outbound identity federation is not enabled, enable it with `aws iam enable-outbound-web-identity-federation`.

## Checks before any write

The plan stops before it creates anything when:

- The management project or a VM target project does not exist, is not `ACTIVE`, or is not in `organization_id` through any folder depth. When the caller cannot read a parent folder, the plan stops with the provider's folder read error.
- An organization audit exemption (`exemptedMembers`) suppresses an audit event that the connector needs. The module does not remove an existing exemption.

## Audit configuration

`google_organization_iam_audit_config` replaces the whole audit configuration of the service it names. The module reads the organization IAM policy during plan and keeps the log types and exemptions that are already set on `allServices` and, with Inspector, on `artifactregistry.googleapis.com`. Folder and project audit configurations are not changed.

## VM scanning and gcloud

Three steps have no provider resource: the organization-scoped and project-scoped OS Config and Progressive Rollout service identities, and the VM Manager `full` feature set. The module runs `gcloud` for them with `local-exec`, so an apply with `target_project_ids` needs the `gcloud` CLI with the beta component on `PATH`. `gcloud` uses the `google` provider's access token, so it acts as the same identity as Terraform. Terraform suppresses the command output because the token is sensitive; if a command fails, run it by hand to see the error. The token expires after about one hour, so apply a saved plan within that time.

## Secrets in Terraform state

The `google_client_config` data source stores the provider's short-lived access token in state. Store the state in an encrypted remote backend with access limited to the people and pipelines that apply this module.

## Existing deployments

This module creates new resources. If a resource with the same name already exists, for example from an earlier setup of the connector, the apply fails on that resource. To manage existing resources, add `import` blocks in your root module. An imported Cloud Asset Inventory feed has `billing_project`, `org_id` and `feed_id` empty in state, so the module ignores changes to those three attributes instead of replacing the feed.

## Destroying

Destroying the module removes everything it created, including resources that other workloads in the organization can share:

- The `allServices` and `artifactregistry.googleapis.com` audit configurations, including log types and exemptions that existed before. To keep them, run `terraform state rm` on `google_organization_iam_audit_config.all_services_write` and `google_organization_iam_audit_config.artifactregistry_read` first.
- The `inspectorFunctionSourceReader` and `OSPolicySSMDeployer` custom roles. A deleted custom role keeps its role ID reserved, so creating it again fails until you undelete the role or GCP completes the deletion.
- The `enable-osconfig` metadata item, which turns off the OS Config agent for every VM in the target projects.

A destroyed workload identity pool stays soft-deleted for 30 days and blocks a new pool with the same name until you undelete it. The service identities and the VM Manager feature set that `gcloud` creates are not removed.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.50 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 6.50 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.50 |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | >= 6.50 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [google-beta_google_project_service_identity.cloud_asset](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_cloud_asset_organization_feed.cai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_asset_organization_feed) | resource |
| [google_compute_project_metadata_item.target_enable_osconfig](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_project_metadata_item) | resource |
| [google_iam_workload_identity_pool.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_logging_organization_sink.inspector_pull](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_logging_organization_sink.lifecycle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_organization_iam_audit_config.all_services_write](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_audit_config) | resource |
| [google_organization_iam_audit_config.artifactregistry_read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_audit_config) | resource |
| [google_organization_iam_custom_role.function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_custom_role.vm_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_organization_iam_member.connector_read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.inspector_function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.org_orchestrator_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_organization_iam_member.vm_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_project_iam_member.cloud_asset_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.target_orchestrator_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
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
| [google_service_account_iam_member.impersonation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [terraform_data.org_service_agents](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.preflight](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.target_service_agents](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.target_vm_manager_full](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [google_client_config.current](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |
| [google_folder.parent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/folder) | data source |
| [google_organization_iam_policy.organization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/organization_iam_policy) | data source |
| [google_project.management](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_project.target](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_projects.checked](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/projects) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from this GCP organization.<br/>`aws_account_id`      - 12-digit AWS account ID. Names the workload identity pool and provider, the service account, the log sinks, the Cloud Asset Inventory feed and the topics.<br/>`aws_region`          - AWS Region of the connector, for example `us-east-1`. Names the Pub/Sub subscriptions and forms their discovery label.<br/>`issuer_url`          - The account's outbound identity federation issuer URL, `https://<id>.tokens.sts.global.api.aws`.<br/>`enable_cspm`         - Enable the CSPM pipeline. Defaults to `true`. The shared AWS Config resources are always created, so this module does not read it; accepted so every connector module takes the same list.<br/>`enable_inspector`    - Enable Amazon Inspector for this account and Region. Defaults to `false`. Adds Inspector federation, Cloud Functions source access, the image-pull log route and the Artifact Registry read audit log.<br/>`enable_inspector_vm` - With `enable_inspector` and a nonempty `target_project_ids`, trust this account's VM scanning role and grant it the OS policy deployer role. Defaults to `true`. Set `false` for an Inspector account that must not get VM access.<br/>An account can appear once per Region. Per-account resources are created once per account; Inspector is on for an account when any of its Regions enables it. | <pre>list(object({<br/>    aws_account_id      = string<br/>    aws_region          = string<br/>    issuer_url          = string<br/>    enable_cspm         = optional(bool, true)<br/>    enable_inspector    = optional(bool, false)<br/>    enable_inspector_vm = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Numeric ID of the GCP organization to onboard. The log sinks, Cloud Asset Inventory feeds, reader roles, custom roles and audit configuration are created at this organization. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID of the GCP management project. It holds the service accounts, workload identity pools, topics and subscriptions, and must be in `organization_id`. Configure it as the provider's billing project. | `string` | n/a | yes |
| <a name="input_permission_model"></a> [permission\_model](#input\_permission\_model) | Read access of the connector service accounts at the organization. `broad` grants `roles/viewer` and the always-on reader roles. `granular` grants the always-on reader roles and one viewer role per supported service. | `string` | `"broad"` | no |
| <a name="input_target_project_ids"></a> [target\_project\_ids](#input\_target\_project\_ids) | Projects whose Compute Engine VMs Amazon Inspector scans. A nonempty list sets up VM scanning for every account that enables Inspector and `enable_inspector_vm`: VM scanning federation, the OS policy deployer role, the OS Config and Progressive Rollout service agents, and VM Manager in each project. Leave empty to skip VM scanning. | `list(string)` | `[]` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_accounts"></a> [accounts](#output\_accounts) | Per-account resources, keyed by AWS account ID. |
| <a name="output_federation_subjects"></a> [federation\_subjects](#output\_federation\_subjects) | AWS IAM role ARNs that each account's workload identity provider trusts, keyed by AWS account ID. |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | GCP organization ID. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Values each onboarded account needs to create its connector, keyed `<aws account>-<aws region>`. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | GCP management project ID. |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | GCP management project number, as used in the workload identity principalSet path. |
