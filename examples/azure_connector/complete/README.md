# Azure connector: complete

Onboards an Azure tenant for every pipeline (CSPM, Amazon Inspector and threat detection) in one Terraform state. The identity that runs it needs the permissions of both the [`azure_connector_entra`](../../../modules/azure\_connector\_entra) and [`azure_connector_arm`](../../../modules/azure\_connector\_arm) modules.

```shell
terraform init
terraform apply \
  -var 'tenant_id=<tenant id>' \
  -var 'subscription_id=<subscription id>' \
  -var lead_aws_account_id=123456789012 \
  -var 'owner_object_ids=["<your Entra object id>"]' \
  -var 'onboarded_accounts=[{aws_account_id="123456789012",aws_region="us-east-1",issuer_url="https://<id>.tokens.sts.global.api.aws"}]'
```

Use `application_client_id`, `tenant_id` and `per_account_connector_inputs` from the outputs when you create the connector in AWS.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.9 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.12 |

### Providers

No providers.

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_azure_connector_arm"></a> [azure\_connector\_arm](#module\_azure\_connector\_arm) | ../../../modules/azure_connector_arm | n/a |
| <a name="module_azure_connector_entra"></a> [azure\_connector\_entra](#module\_azure\_connector\_entra) | ../../../modules/azure_connector_entra | n/a |

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_lead_aws_account_id"></a> [lead\_aws\_account\_id](#input\_lead\_aws\_account\_id) | AWS account ID used to name the shared Azure resources. | `string` | n/a | yes |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from the Azure tenant. See the module documentation for the object attributes. | <pre>list(object({<br/>    aws_account_id   = string<br/>    aws_region       = string<br/>    issuer_url       = string<br/>    enable_cspm      = optional(bool, true)<br/>    enable_inspector = optional(bool, true)<br/>    enable_threats   = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_owner_object_ids"></a> [owner\_object\_ids](#input\_owner\_object\_ids) | Entra object IDs that own the application and service principal. | `set(string)` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription that hosts the Event Hub namespaces. | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Azure tenant ID to onboard. | `string` | n/a | yes |
| <a name="input_azure_locations"></a> [azure\_locations](#input\_azure\_locations) | Azure locations that contain container registries for Amazon Inspector to scan. | `list(string)` | <pre>[<br/>  "eastus"<br/>]</pre> | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_client_id"></a> [application\_client\_id](#output\_application\_client\_id) | Application (client) ID to enter when you create the connector in AWS. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Connector inputs for each onboarded account and Region. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure tenant ID. |
