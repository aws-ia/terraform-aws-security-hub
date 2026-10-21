# Azure connector: Azure resources only

The second half of a split deployment. An Azure administrator applies this example in its own state, using the outputs of the [`entra_only`](../entra\_only) example and the same `lead_aws_account_id` and `onboarded_accounts`. It defaults `azure_locations` to an empty list, so set it when any account enables Amazon Inspector.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.12 |

### Providers

No providers.

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_azure_connector_arm"></a> [azure\_connector\_arm](#module\_azure\_connector\_arm) | ../../../modules/azure_connector_arm | n/a |

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_client_id"></a> [application\_client\_id](#input\_application\_client\_id) | Application (client) ID, from the entra\_only example. | `string` | n/a | yes |
| <a name="input_lead_aws_account_id"></a> [lead\_aws\_account\_id](#input\_lead\_aws\_account\_id) | AWS account ID used to name the shared Azure resources. Use the same value as the entra\_only example. | `string` | n/a | yes |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from the Azure tenant. Use the same list as the entra\_only example. | <pre>list(object({<br/>    aws_account_id   = string<br/>    aws_region       = string<br/>    issuer_url       = string<br/>    enable_cspm      = optional(bool, true)<br/>    enable_inspector = optional(bool, true)<br/>    enable_threats   = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_service_principal_object_id"></a> [service\_principal\_object\_id](#input\_service\_principal\_object\_id) | Service principal object ID, from the entra\_only example. | `string` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription that hosts the Event Hub namespaces. | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Azure tenant ID, from the entra\_only example. | `string` | n/a | yes |
| <a name="input_azure_locations"></a> [azure\_locations](#input\_azure\_locations) | Azure locations that contain container registries for Amazon Inspector to scan. | `list(string)` | `[]` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Connector inputs for each onboarded account and Region. |
| <a name="output_remediation_subscription_ids"></a> [remediation\_subscription\_ids](#output\_remediation\_subscription\_ids) | Subscriptions that received provider registrations and compliance scans. |
