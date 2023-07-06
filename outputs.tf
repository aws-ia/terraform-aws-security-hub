##################################################
# Security Hub
##################################################
output "securityhub_account" {
  description = "Security Hub AWS account configuration."
  value       = aws_securityhub_account.this
}

output "finding_aggregator" {
  description = "Security Hub finding aggregator configuration."
  value       = aws_securityhub_finding_aggregator.this
}

##################################################
# Security Hub Subscriptions
##################################################
output "product_subscription" {
  description = "Security Hub products subscriptions."
  value       = aws_securityhub_product_subscription.this
}

output "standards_subscription" {
  description = "Security Hub compliance standards subscriptions."
  value       = aws_securityhub_standards_subscription.this
}

##################################################
# Security Hub Action Targets
##################################################
output "action_target" {
  description = "Security Hub custome action targets."
  value       = aws_securityhub_action_target.this
}
