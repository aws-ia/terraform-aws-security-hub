## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.47 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.67.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_standalone_security_hub"></a> [standalone\_security\_hub](#module\_standalone\_security\_hub) | ../../../ | n/a |

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
| <a name="output_insights"></a> [insights](#output\_insights) | AWS Security Hub Custom Insights |
| <a name="output_security_hub"></a> [security\_hub](#output\_security\_hub) | AWS Security Hub Standalone deploymeent |
| <a name="output_standards_control"></a> [standards\_control](#output\_standards\_control) | AWS Security Hub Standards Control Customization |
