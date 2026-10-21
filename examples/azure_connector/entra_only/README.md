# Azure connector: Entra ID only

The first half of a split deployment, for when a directory administrator and an Azure administrator are different people. A Global Administrator, or a Privileged Role Administrator who is also an Application Administrator or Cloud Application Administrator, applies this example; it needs no subscription access. Pass its outputs, and the same `lead_aws_account_id` and `onboarded_accounts`, to the [`arm_only`](../arm\_only) example.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 3.0 |

### Providers

No providers.

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_azure_connector_entra"></a> [azure\_connector\_entra](#module\_azure\_connector\_entra) | ../../../modules/azure_connector_entra | n/a |

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_lead_aws_account_id"></a> [lead\_aws\_account\_id](#input\_lead\_aws\_account\_id) | AWS account ID used to name the shared Azure resources. Use the same value in the arm\_only example. | `string` | n/a | yes |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from the Azure tenant. Use the same list in the arm\_only example. | <pre>list(object({<br/>    aws_account_id   = string<br/>    aws_region       = string<br/>    issuer_url       = string<br/>    enable_cspm      = optional(bool, true)<br/>    enable_inspector = optional(bool, true)<br/>    enable_threats   = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_owner_object_ids"></a> [owner\_object\_ids](#input\_owner\_object\_ids) | Entra object IDs that own the application and service principal. | `set(string)` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Azure tenant ID to onboard. | `string` | n/a | yes |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_client_id"></a> [application\_client\_id](#output\_application\_client\_id) | Application (client) ID. Input to the arm\_only example and to the connector in AWS. |
| <a name="output_service_principal_object_id"></a> [service\_principal\_object\_id](#output\_service\_principal\_object\_id) | Service principal object ID. Input to the arm\_only example. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure tenant ID. Input to the arm\_only example. |
