output "security_hub" {
  description = "AWS Security Hub Standalone deploymeent"
  value       = module.standalone_security_hub
}

output "standards_control" {
  description = "AWS Security Hub Standards Control Customization"
  value       = aws_securityhub_standards_control.ensure_iam_password_policy_prevents_password_reuse
}

output "insights" {
  description = "AWS Security Hub Custom Insights"
  value       = aws_securityhub_insight.this
}