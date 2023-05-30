variable "member_config" {
  description = <<EOF
  Specifies the member account configuration:
  `account_id`                 - The 13 digit ID number of the member account. Example: `123456789012`.
  `email`                      - Email address to send the invite for member account. Defaults to `null`.
  `invite`                     - Whether to invite the account to SecurityHub as a member. Defaults to `false`. To detect if an invitation needs to be (re-)sent, the Terraform state value is true based on a `member_status` of `Disabled` | `Enabled` |  `Invited` |  EmailVerificationInProgress.
  EOF
  type = list(object({
    account_id = number
    email      = string
    invite     = bool
  }))
  default = null
}