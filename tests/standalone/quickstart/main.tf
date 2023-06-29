provider "aws" {}

module "standalone_security_hub" {
  source = "../../../"

  enable_default_standards  = true
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = true
}
