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

| Name | Source | Version |
|------|--------|---------|
| <a name="module_delegated_admin"></a> [delegated\_admin](#module\_delegated\_admin) | ../../../modules/organizations_admin/ | n/a |
| <a name="module_member_account"></a> [member\_account](#module\_member\_account) | ../../../modules/organizations_member/ | n/a |
| <a name="module_organizations_security_hub"></a> [organizations\_security\_hub](#module\_organizations\_security\_hub) | ../../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_securityhub_insight.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_insight) | resource |
| [aws_securityhub_standards_control.ensure_iam_password_policy_prevents_password_reuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_control) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_delegated_admin"></a> [delegated\_admin](#output\_delegated\_admin) | AWS Security Hub delegated admin |
