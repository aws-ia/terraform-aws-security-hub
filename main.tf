resource "aws_securityhub_account" "this" {
  enable_default_standards  = var.enable_default_standards
  control_finding_generator = var.control_finding_generator
  auto_enable_controls      = var.auto_enable_controls
}

resource "aws_securityhub_finding_aggregator" "this" {
  linking_mode      = var.linking_mode
  specified_regions = var.specified_regions

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_product_subscription" "this" {
  for_each    = var.product_config != null ? { for product in var.product_config : product.arn => product } : {}
  product_arn = each.value.arn

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "this" {
  for_each = var.standards_config != null ? { for standards in local.standards_subscription : standards.arn => standards if standards.enable } : {}

  standards_arn = each.value.arn

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_action_target" "this" {
  for_each = var.action_target != null ? { for target in var.action_target : target.identifier => target } : {}

  name        = each.value.name
  identifier  = each.value.identifier
  description = each.value.description

  depends_on = [aws_securityhub_account.this]
}
