provider "aws" {}

module "standalone_security_hub" {
  source  = "aws-ia/security-hub/aws"
  version = "0.0.1"

  enable_default_standards  = true
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = true
}
