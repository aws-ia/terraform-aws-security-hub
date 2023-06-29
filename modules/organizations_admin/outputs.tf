output "securityhub_delegated_admin_account" {
  description = "AWS Security Hub Delegated Admin account."
  value       = aws_securityhub_organization_admin_account.this
}

output "securityhub_organization_configuration" {
  description = "AWS Security Hub Organizations configuration."
  value       = aws_securityhub_organization_configuration.this
}
