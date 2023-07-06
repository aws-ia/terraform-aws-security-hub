## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.47 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.47 |
| <a name="provider_aws.member"></a> [aws.member](#provider\_aws.member) | >= 4.47 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_securityhub_account.member](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_invite_accepter.member](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_invite_accepter) | resource |
| [aws_securityhub_member.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_member_config"></a> [member\_config](#input\_member\_config) | Specifies the member account configuration:<br>  `account_id`                 - The 13 digit ID number of the member account. Example: `123456789012`.<br>  `email`                      - Email address to send the invite for member account. Defaults to `null`.<br>  `invite`                     - Whether to invite the account to SecurityHub as a member. Defaults to `false`. To detect if an invitation needs to be (re-)sent, the Terraform state value is true based on a `member_status` of `Disabled` \| `Enabled` \|  `Invited` \|  EmailVerificationInProgress. | <pre>list(object({<br>    account_id = number<br>    email      = string<br>    invite     = bool<br>  }))</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_securityhub_member"></a> [securityhub\_member](#output\_securityhub\_member) | AWS Security Hub member configuration. |
| <a name="output_securityhub_member_account"></a> [securityhub\_member\_account](#output\_securityhub\_member\_account) | AWS Security Hub member account configuration. |
| <a name="output_securityhub_member_invite"></a> [securityhub\_member\_invite](#output\_securityhub\_member\_invite) | AWS Security Hub organizations invite. |
