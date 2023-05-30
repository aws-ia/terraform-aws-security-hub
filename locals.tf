locals {
  standards_subscription = {
    aws_foundational_security_best_practices = var.standards_config != null ? merge(var.standards_config.aws_foundational_security_best_practices,
      {
        arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
    }) : null
    cis_aws_foundations_benchmark_v120 = var.standards_config != null ? merge(var.standards_config.cis_aws_foundations_benchmark_v120,
      {
        arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
    }) : null
    cis_aws_foundations_benchmark_v140 = var.standards_config != null ?  merge(var.standards_config.cis_aws_foundations_benchmark_v140,
      {
        arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"
    }) : null
    nist_sp_800_53_rev5 = var.standards_config != null ? merge(var.standards_config.nist_sp_800_53_rev5,
      {
        arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/nist-800-53/v/5.0.0"
    }) : null
    pci_dss = var.standards_config != null ? merge(var.standards_config.pci_dss,
      {
        arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/pci-dss/v/3.2.1"
    }) : null
  }
}