# AWS Security Hub Azure connector: Entra ID

Creates the Microsoft Entra ID objects that let AWS Security Hub, AWS Config and Amazon Inspector read an Azure tenant without stored secrets:

- An application registration with an `api://<client id>` identifier URI, and its service principal.
- Federated identity credentials that trust each AWS account's outbound identity federation issuer. Each account gets one for AWS Config, two for Amazon Inspector and one for Security Hub threat detection, depending on the pipelines it enables.
- Admin consent for twelve read-only Microsoft Graph application permissions.

Use it with the [`azure_connector_arm`](../azure\_connector\_arm) module, which creates the Azure resources and role assignments for the service principal. Both modules take the same `onboarded_accounts` and `lead_aws_account_id`.

## Permissions

The `azuread` provider identity needs Global Administrator, or both Privileged Role Administrator (to grant admin consent for the Microsoft Graph application permissions) and Application Administrator or Cloud Application Administrator (to create the application registration and service principal). It needs no Azure subscription access, so a directory administrator can apply this module separately from the Azure resources.

## Usage

```hcl
provider "azuread" {
  tenant_id = "00000000-0000-0000-0000-000000000000"
}

module "azure_connector_entra" {
  source = "aws-ia/security-hub/aws//modules/azure_connector_entra"

  lead_aws_account_id = "123456789012"
  owner_object_ids    = ["00000000-0000-0000-0000-000000000000"]
  onboarded_accounts = [{
    aws_account_id = "123456789012"
    aws_region     = "us-east-1"
    issuer_url     = "https://00000000-0000-0000-0000-000000000000.tokens.sts.global.api.aws"
  }]
}
```

Get an account's issuer URL with `aws iam get-outbound-web-identity-federation-info`. If outbound identity federation is not enabled, enable it with `aws iam enable-outbound-web-identity-federation`.

## Limits

Entra allows 20 federated identity credentials per application, so one application can serve five accounts that enable every pipeline. The module rejects a configuration that needs more.

## Existing deployments

This module creates new objects. If the tenant already has an application with the same display name, the apply fails instead of creating a duplicate. To manage existing objects, add `import` blocks in your root module.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 3.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | >= 3.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [azuread_app_role_assignment.graph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/app_role_assignment) | resource |
| [azuread_application.connector](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_federated_identity_credential.aws](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_federated_identity_credential) | resource |
| [azuread_application_identifier_uri.connector](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_identifier_uri) | resource |
| [azuread_service_principal.connector](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azuread_application_published_app_ids.well_known](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/application_published_app_ids) | data source |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_service_principal.msgraph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_lead_aws_account_id"></a> [lead\_aws\_account\_id](#input\_lead\_aws\_account\_id) | AWS account ID used to name the shared Azure resources, for example `AWSAuthApp-<id>`. It does not need to be in `onboarded_accounts`. Changing it renames the application. | `string` | n/a | yes |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and region pairs that read from this Azure tenant. Pass the same list to the `azure_connector_arm` module.<br/>`aws_account_id`   - 12-digit AWS account ID.<br/>`aws_region`       - AWS Region that reads the Azure data, for example `us-east-1`.<br/>`issuer_url`       - The account's outbound identity federation issuer URL, `https://<id>.tokens.sts.global.api.aws`.<br/>`enable_cspm`      - Enable the CSPM pipeline. Defaults to `true`. Not used by this module; accepted so both modules take the same list.<br/>`enable_inspector` - Create the federated credentials for Amazon Inspector. Defaults to `true`.<br/>`enable_threats`   - Create the federated credential for Security Hub threat detection. Defaults to `true`.<br/>An account can appear once per Region. Federated credentials are created once per account, and every account gets the AWS Config credential. | <pre>list(object({<br/>    aws_account_id   = string<br/>    aws_region       = string<br/>    issuer_url       = string<br/>    enable_cspm      = optional(bool, true)<br/>    enable_inspector = optional(bool, true)<br/>    enable_threats   = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_owner_object_ids"></a> [owner\_object\_ids](#input\_owner\_object\_ids) | Entra object IDs that own the application and service principal. Terraform manages this set, so include every owner you want to keep, and keep it the same when a different identity runs Terraform. | `set(string)` | n/a | yes |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Display name of the Entra application registration. Defaults to `AWSAuthApp-<lead_aws_account_id>`. | `string` | `null` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_client_id"></a> [application\_client\_id](#output\_application\_client\_id) | Application (client) ID of the Entra application registration. Required when you create the connector in AWS. |
| <a name="output_application_display_name"></a> [application\_display\_name](#output\_application\_display\_name) | Display name of the Entra application registration. |
| <a name="output_application_object_id"></a> [application\_object\_id](#output\_application\_object\_id) | Object ID of the Entra application registration. |
| <a name="output_federated_credentials"></a> [federated\_credentials](#output\_federated\_credentials) | Federated identity credentials on the application, keyed `<aws account>-<purpose>`. |
| <a name="output_graph_permissions"></a> [graph\_permissions](#output\_graph\_permissions) | Microsoft Graph application permissions granted to the service principal. |
| <a name="output_identifier_uri"></a> [identifier\_uri](#output\_identifier\_uri) | Application ID URI, `api://<client id>`. |
| <a name="output_service_principal_object_id"></a> [service\_principal\_object\_id](#output\_service\_principal\_object\_id) | Object ID of the service principal. Pass it to the `azure_connector_arm` module. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure tenant ID that the `azuread` provider is authenticated to. |
