## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.47 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_securityhub_organization_admin_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_admin_account) | resource |
| [aws_securityhub_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_configuration) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_account_id"></a> [admin\_account\_id](#input\_admin\_account\_id) | AWS Organizations Admin Account Id. Defaults to `null` | `string` | `null` | no |
| <a name="input_auto_enable_standards"></a> [auto\_enable\_standards](#input\_auto\_enable\_standards) | Automatically enable Security Hub default standards for new member accounts in the organization. To opt-out of enabling default standards, set to `NONE`. Defaults to `DEFAULT`. | `string` | `"DEFAULT"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_securityhub_delegated_admin_account"></a> [securityhub\_delegated\_admin\_account](#output\_securityhub\_delegated\_admin\_account) | AWS Security Hub Delegated Admin account. |
| <a name="output_securityhub_organization_configuration"></a> [securityhub\_organization\_configuration](#output\_securityhub\_organization\_configuration) | AWS Security Hub Organizations configuration. |
