##################################################
# Security Hub Delegated Admin
##################################################
resource "aws_securityhub_organization_admin_account" "this" {
  count            = var.admin_account_id == null ? 0 : 1
  admin_account_id = var.admin_account_id
}

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = true
  auto_enable_standards = var.auto_enable_standards

  depends_on = [aws_securityhub_organization_admin_account.this]
}
