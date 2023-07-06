output "delegated_admin" {
  description = "AWS Security Hub Delegated admin."
  value       = module.delegated_admin
}

output "organizations_security_hub" {
  description = "Organizations AWS Security Hub Configuration."
  value       = module.organizations_security_hub
}

output "member" {
  description = "Organizations account member AWS Security Hub."
  value       = module.member_account
}
