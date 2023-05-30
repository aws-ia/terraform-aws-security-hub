resource "aws_securityhub_account" "member" {
  for_each = var.member_config != null ? { for member in var.member_config : member.account_id => member } : {}
  provider = aws.member
}

resource "aws_securityhub_member" "this" {
  for_each = var.member_config != null ? { for member in var.member_config : member.account_id => member } : {}

  account_id = each.value.account_id
  email      = each.value.email
  invite     = each.value.invite
}