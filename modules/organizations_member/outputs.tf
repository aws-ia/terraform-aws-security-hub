output "securityhub_member" {
  description = "AWS Security Hub member configuration."
  value       = aws_securityhub_member.this
}

output "securityhub_member_account" {
  description = "AWS Security Hub member account configuration."
  value       = aws_securityhub_account.member
}

output "securityhub_member_invite" {
  description = "AWS Security Hub organizations invite."
  value       = aws_securityhub_invite_accepter.member
}
