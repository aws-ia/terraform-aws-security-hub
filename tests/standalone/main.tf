provider "aws" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

module "standalone_security_hub" {
  source = "../../"

  enable_default_standards  = false
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = true

  product_config = [{
    enable = true
    arn    = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  }]

  standards_config = {
    aws_foundational_security_best_practices = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v120 = {
      enable = false
    }
    cis_aws_foundations_benchmark_v140 = {
      enable = true
      status = "ENABLED"
    }
    nist_sp_800_53_rev5 = {
      enable = false
    }
    pci_dss = {
      enable = false
    }
  }
  
  action_target = [{
    name        = "Send to Amazon SNS"
    identifier  = "SendToSNS"
    description = "This is a custom action to send findings to SNS Topic"
  }]

}