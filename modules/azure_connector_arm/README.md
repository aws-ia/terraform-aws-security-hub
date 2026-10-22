# AWS Security Hub Azure connector: Azure resources

Creates the Azure resources that stream an Azure tenant's data to AWS Security Hub, AWS Config and Amazon Inspector, and grants the connector's service principal access to read them. Policies and most role assignments are scoped to the tenant root management group, so they cover every current and future subscription. The connector's Reader role is assigned at the root scope `/`.

| Pipeline | Enabled by | Resources |
|----------|-----------|-----------|
| Shared | always | Resource group, Event Hub namespace with an `activitylog` hub, one consumer group per account and Region, Reader at `/`, Event Hubs Data Receiver at the root management group |
| CSPM | `enable_cspm` | Activity Log diagnostic settings policy, Entra ID log diagnostic setting |
| Inspector | `enable_inspector` | Activity Log policy, one Event Hub namespace and ACR diagnostic settings policy per entry in `azure_locations`, two policies that add a system-assigned identity to VMs, a VM Run Command custom role, Contributor at the root management group |
| Threats | `enable_threats` | `defender-alerts` hub with a send-only rule, Defender for Cloud continuous export policy |

The connector's Event Hubs Data Receiver role is at the tenant root management group, so one assignment covers every namespace this module creates. It also lets the connector receive from every other Event Hub namespace in the tenant. When Inspector is enabled, the connector's Contributor role at the same scope already grants that reach; for a CSPM- or threats-only deployment, this assignment is the broader access.

The namespaces carry discovery tags (`AWSConfig-<account>-<region>`, `AWSSecurityHub-<account>-<region>`) that the connector uses to find its Event Hub and consumer group.

Use it with the [`azure_connector_entra`](../azure\_connector\_entra) module, which creates the service principal. Pass both modules the same `onboarded_accounts` and `lead_aws_account_id`.

## Permissions

The `azurerm` and `azapi` provider identity needs:

- Owner, or Contributor and User Access Administrator, at the tenant root management group.
- User Access Administrator at the root scope `/`, for the connector's Reader role assignment there. A Global Administrator can get this by [elevating access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin). Terraform reads that assignment on every plan, so keep at least Reader at `/` for as long as Terraform manages this module, and User Access Administrator at `/` for any apply or destroy that changes it.
- Global Administrator or Security Administrator, when any account enables CSPM, to create the tenant-level Entra ID diagnostic setting.

## Usage

```hcl
provider "azurerm" {
  features {}
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

provider "azapi" {
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

module "azure_connector_arm" {
  source = "aws-ia/security-hub/aws//modules/azure_connector_arm"

  lead_aws_account_id         = "123456789012"
  service_principal_object_id = module.azure_connector_entra.service_principal_object_id
  application_client_id       = module.azure_connector_entra.application_client_id
  tenant_id                   = module.azure_connector_entra.tenant_id
  azure_locations             = ["eastus"]

  onboarded_accounts = [{
    aws_account_id = "123456789012"
    aws_region     = "us-east-1"
    issuer_url     = "https://00000000-0000-0000-0000-000000000000.tokens.sts.global.api.aws"
  }]
}
```

## Existing resources and remediation

DeployIfNotExists and modify policies act only on resources created or updated after the assignment. For resources that already exist, the module creates one remediation task per policy assignment at the tenant root management group, so each task covers every subscription in the tenant. Set `create_policy_remediations = false` to skip remediation.

The Defender for Cloud export policy treats a subscription's automation as compliant only when it is enabled, scoped to that subscription, exports only alerts, and sends to the `defender-alerts` hub through the `DefenderExportSend` rule. An automation that has been disabled or changed is reported as non-compliant, and a remediation task redeploys it.

A management group remediation task only fixes resources that Azure has already evaluated as non-compliant, and a new assignment has no compliance results yet. Before it creates the tasks, the module therefore starts an on-demand compliance scan in each subscription and waits for it to finish, for up to `compliance_scan_timeout` (default `60m`) per subscription. By default the scanned subscriptions are every enabled subscription in the tenant that the `azurerm` identity can read. Set `remediation_subscription_ids` to limit them. In a subscription that is not scanned, a task fixes only the resources Azure had already evaluated when the task started.

The module also requests registration of the resource providers that the policies deploy (`Microsoft.Insights`, `Microsoft.EventHub`, `Microsoft.PolicyInsights`, and `Microsoft.Security` for threats) in the same subscriptions, and registers `Microsoft.PolicyInsights` on the tenant root management group, which management group remediation tasks with a large `remediation_resource_count` require. It does not wait for registration to finish. If the first apply fails with `ManagementGroupNotRegistered`, wait a few minutes for the registration to propagate and apply again. Set `register_resource_providers = false` if you manage registration elsewhere; then register `Microsoft.PolicyInsights` on the root management group yourself before raising `remediation_resource_count`.

Terraform creates the remediation tasks but does not wait for them to finish, so a task that fails inside Azure still shows as created. After the first apply, check the tasks in **Azure Policy > Remediation**. Common causes of a failed deployment are a resource provider that was still registering, a managed identity role that had not propagated yet, and a subscription that already has the five Activity Log diagnostic settings Azure allows. Each task fixes at most `remediation_resource_count` resources, which defaults to Azure's default of 500. Azure allows up to 50,000; raise it if a policy has more non-compliant resources than that in your tenant. To run a task again, replace it, using the assignment key from the `existing_resources` addresses in state (for example `activity`, `defender` or `acr-eus`):

```shell
terraform apply -replace='module.azure_connector_arm.azurerm_management_group_policy_remediation.existing_resources["<assignment key>"]'
```

The scans run again and the tasks are replaced when a policy rule or its parameters change, and when a subscription is added to or removed from the scanned list.

Azure Policy deletes a remediation task 60 days after it was last modified. After that, a plan shows the module's remediation tasks as resources to create. Applying it is safe: each new task fixes only resources that are not compliant. To stop these plans once your existing resources are remediated, set `create_policy_remediations = false`. The policies still configure new and updated resources without remediation tasks.

## Secrets in Terraform state

The `azurerm` provider reads Event Hub access keys into Terraform state: the `RootManageSharedAccessKey` primary and secondary keys and connection strings of the shared and regional namespaces, and the keys of the `DefenderExportSend` rule. Marking outputs sensitive does not remove them from state. Anyone who can read the state can send to and receive from every Event Hub in these namespaces, and manage them. Store the state in an encrypted remote backend with access limited to the people and pipelines that apply this module, and rotate the keys in **Event Hubs > Shared access policies** if the state is exposed.

## Limits

- Standard tier Event Hubs allow 20 consumer groups per hub, including `$Default`, so `onboarded_accounts` can have at most 19 entries.
- A resource can have 50 tags. The shared namespace uses one tag per entry in `onboarded_accounts` and one per threats-enabled entry.
- Microsoft Entra ID allows 5 tenant-level diagnostic settings. When any account enables CSPM, the module adds one, so the apply fails in a tenant that already has 5.
- Each ACR location adds a short token to the regional namespace name, `<event_hub_namespace_name>-<token>`, which must be at most 50 characters. With a long `event_hub_namespace_name`, set shorter tokens in `azure_location_tokens`.

## Existing deployments

This module creates new resources. One deployment of this module should manage a tenant. If the shared resources already exist, the apply fails on the first conflicting resource; to manage existing resources, add `import` blocks in your root module.

Destroying the module removes the policy assignments and Event Hubs. It does not remove the diagnostic settings, Defender for Cloud automations, resource groups or VM identities that the policies created in your subscriptions.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.12 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.9 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.12 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [azapi_resource.entra_diagnostics](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.sp_reader](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource_action.compliance_scan](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_resource_action.register_policy_insights_mg](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource_action) | resource |
| [azapi_resource_action.register_provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource_action) | resource |
| [azurerm_eventhub.acr_activity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub.activity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub.defender](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub_authorization_rule.defender_send](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_authorization_rule) | resource |
| [azurerm_eventhub_consumer_group.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_consumer_group) | resource |
| [azurerm_eventhub_consumer_group.activity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_consumer_group) | resource |
| [azurerm_eventhub_consumer_group.defender](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_consumer_group) | resource |
| [azurerm_eventhub_namespace.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace) | resource |
| [azurerm_eventhub_namespace.shared](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace) | resource |
| [azurerm_management_group_policy_assignment.acr_diagnostics](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_assignment.activity_log](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_assignment.defender_export](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_assignment.vm_identity_none](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_assignment.vm_identity_ua](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_remediation.existing_resources](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_remediation) | resource |
| [azurerm_policy_definition.acr_diagnostics](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_policy_definition.activity_log](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_policy_definition.defender_export](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_policy_definition.vm_identity_none](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_policy_definition.vm_identity_ua](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_resource_group.eventhub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.policy_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.policy_eventhubs_data_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.sp_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.sp_eventhubs_data_receiver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.sp_vm_runcommand](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.vm_runcommand](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [terraform_data.compliance_scan_generation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.policy_generation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [azapi_client_config.current](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/client_config) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_subscriptions.available](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscriptions) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_client_id"></a> [application\_client\_id](#input\_application\_client\_id) | Application (client) ID of the connector application, from the `application_client_id` output of the `azure_connector_entra` module. Used only in outputs. | `string` | n/a | yes |
| <a name="input_lead_aws_account_id"></a> [lead\_aws\_account\_id](#input\_lead\_aws\_account\_id) | AWS account ID used to name the shared Azure resources, for example `aws-eh-<id>`. Use the same value as the `azure_connector_entra` module. Changing it renames, and therefore replaces, the Event Hub namespaces and policies. | `string` | n/a | yes |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and region pairs that read from this Azure tenant. Pass the same list to the `azure_connector_entra` module.<br/>`aws_account_id`   - 12-digit AWS account ID.<br/>`aws_region`       - AWS Region that reads the Azure data, for example `us-east-1`.<br/>`issuer_url`       - The account's outbound identity federation issuer URL. Not used by this module; accepted so both modules take the same list.<br/>`enable_cspm`      - Enable the CSPM pipeline (subscription Activity Log and Entra ID logs). Defaults to `true`.<br/>`enable_inspector` - Enable the Amazon Inspector pipeline (ACR events, VM identities, VM Run Command). Defaults to `true`.<br/>`enable_threats`   - Enable the threat detection pipeline (Defender for Cloud alert export). Defaults to `true`.<br/>Policies, diagnostic settings and role assignments are tenant-wide. They are created when any account enables the pipeline that needs them. | <pre>list(object({<br/>    aws_account_id   = string<br/>    aws_region       = string<br/>    issuer_url       = string<br/>    enable_cspm      = optional(bool, true)<br/>    enable_inspector = optional(bool, true)<br/>    enable_threats   = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_service_principal_object_id"></a> [service\_principal\_object\_id](#input\_service\_principal\_object\_id) | Object ID of the connector service principal, from the `service_principal_object_id` output of the `azure_connector_entra` module. | `string` | n/a | yes |
| <a name="input_azure_location_tokens"></a> [azure\_location\_tokens](#input\_azure\_location\_tokens) | Overrides for the short location token used in regional resource names, keyed by Azure location. Locations without an override use a built-in token or the first 6 characters of the location's MD5 hash. | `map(string)` | `{}` | no |
| <a name="input_azure_locations"></a> [azure\_locations](#input\_azure\_locations) | Azure locations that contain container registries to scan. Each gets a regional Event Hub namespace, because ACR diagnostic settings can only send to an Event Hub in the same location. Required when any account enables Inspector. | `list(string)` | `[]` | no |
| <a name="input_compliance_scan_timeout"></a> [compliance\_scan\_timeout](#input\_compliance\_scan\_timeout) | How long to wait for the compliance scan of each subscription before remediation, as a Terraform duration such as `60m`. A subscription with many resources takes longer to scan. | `string` | `"60m"` | no |
| <a name="input_create_policy_remediations"></a> [create\_policy\_remediations](#input\_create\_policy\_remediations) | Scan subscriptions for compliance and create one policy remediation task per policy assignment at the tenant root management group, so the policies also configure resources that existed before the assignments. Without them the policies only act on resources created or updated afterwards. | `bool` | `true` | no |
| <a name="input_event_hub_location"></a> [event\_hub\_location](#input\_event\_hub\_location) | Azure location of the shared Event Hub namespace. Also the location of the policy assignment managed identities. Changing it replaces the namespace. | `string` | `"eastus"` | no |
| <a name="input_event_hub_namespace_name"></a> [event\_hub\_namespace\_name](#input\_event\_hub\_namespace\_name) | Name of the shared Event Hub namespace, which must be globally unique. Defaults to `aws-eh-<lead_aws_account_id>`. Regional namespaces append `-<location token>`. | `string` | `null` | no |
| <a name="input_event_hub_resource_group_name"></a> [event\_hub\_resource\_group\_name](#input\_event\_hub\_resource\_group\_name) | Name of the resource group to create for the Event Hub namespaces, in the `azurerm` provider's subscription. | `string` | `"aws-eventhub-rg"` | no |
| <a name="input_register_resource_providers"></a> [register\_resource\_providers](#input\_register\_resource\_providers) | Register the Microsoft.Insights, Microsoft.EventHub and Microsoft.PolicyInsights resource providers (and Microsoft.Security when threats are enabled) in every subscription in `remediation_subscription_ids`, and Microsoft.PolicyInsights on the tenant root management group when `create_policy_remediations` is true. Registration is requested but not awaited. | `bool` | `true` | no |
| <a name="input_remediation_resource_count"></a> [remediation\_resource\_count](#input\_remediation\_resource\_count) | Maximum number of non-compliant resources each remediation task fixes. Azure's default is 500 and its maximum is 50,000. Raise it for a tenant with more resources per policy than that. | `number` | `500` | no |
| <a name="input_remediation_subscription_ids"></a> [remediation\_subscription\_ids](#input\_remediation\_subscription\_ids) | Subscriptions to register resource providers in and scan for compliance before remediation. Defaults to every enabled subscription in the tenant that the `azurerm` identity can read. The remediation tasks cover every subscription under the tenant root management group; a subscription left out is not scanned, so only resources Azure has already evaluated there are fixed. | `list(string)` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for the resource group and Event Hub namespaces. The module also adds, to the namespaces, the discovery tags the connector uses to find the Event Hubs. | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Expected Azure tenant ID. When set, the plan fails if the `azurerm` provider is authenticated to a different tenant. Pass the `tenant_id` output of the `azure_connector_entra` module. | `string` | `null` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_discovery_tags"></a> [discovery\_tags](#output\_discovery\_tags) | Tags on the shared namespace that AWS Config and Security Hub use to find the Event Hubs and consumer groups. |
| <a name="output_event_hub_namespace_fqdn"></a> [event\_hub\_namespace\_fqdn](#output\_event\_hub\_namespace\_fqdn) | Fully qualified domain name of the shared Event Hub namespace. |
| <a name="output_event_hub_namespace_name"></a> [event\_hub\_namespace\_name](#output\_event\_hub\_namespace\_name) | Name of the shared Event Hub namespace. |
| <a name="output_event_hub_resource_group_name"></a> [event\_hub\_resource\_group\_name](#output\_event\_hub\_resource\_group\_name) | Resource group that holds the Event Hub namespaces. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Values each onboarded account needs to create its connector, keyed `<aws account>-<aws region>`. |
| <a name="output_policy_assignment_ids"></a> [policy\_assignment\_ids](#output\_policy\_assignment\_ids) | Management group policy assignments created by the module. |
| <a name="output_regional_acr_namespaces"></a> [regional\_acr\_namespaces](#output\_regional\_acr\_namespaces) | Regional Event Hub namespaces for container registry events, keyed by location token. |
| <a name="output_remediation_subscription_ids"></a> [remediation\_subscription\_ids](#output\_remediation\_subscription\_ids) | Subscriptions that received provider registrations and compliance scans. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure tenant ID that the `azurerm` provider is authenticated to. |
