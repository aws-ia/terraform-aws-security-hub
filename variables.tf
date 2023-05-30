variable "enable_default_standards" {
  description = "Whether to enable the security standards that Security Hub has designated as automatically enabled including: AWS Foundational Security Best Practices v1.0.0 and CIS AWS Foundations Benchmark v1.2.0. Defaults to `true`."
  type        = bool
  default     = true
}

variable "control_finding_generator" {
  description = "Updates whether the calling account has consolidated control findings turned on. If the value for this field is set to SECURITY_CONTROL, Security Hub generates a single finding for a control check even when the check applies to multiple enabled standards. If the value for this field is set to STANDARD_CONTROL, Security Hub generates separate findings for a control check when the check applies to multiple enabled standards. For accounts that are part of an organization, this value can only be updated in the administrator account."
  type        = string
  default     = "STANDARD_CONTROL"
}

variable "auto_enable_controls" {
  description = "Whether to automatically enable new controls when they are added to standards that are enabled. By default, this is set to true, and new controls are enabled automatically. To not automatically enable new controls, set this to false."
  type        = bool
  default     = true
}

variable "product_config" {
  description = "The ARN of the product that generates findings that you want to import into Security Hub."
  type = list(object({
    enable = bool
    arn    = string
  }))
  default = null
}

variable "linking_mode" {
  description = "Indicates whether to aggregate findings from all of the available Regions or from a specified list. The options are ALL_REGIONS, ALL_REGIONS_EXCEPT_SPECIFIED or SPECIFIED_REGIONS. When ALL_REGIONS or ALL_REGIONS_EXCEPT_SPECIFIED are used, Security Hub will automatically aggregate findings from new Regions as Security Hub supports them and you opt into them."
  type        = string
  default     = "ALL_REGIONS"
}

variable "specified_regions" {
  description = "List of regions to include or exclude (required if linking_mode is set to ALL_REGIONS_EXCEPT_SPECIFIED or SPECIFIED_REGIONS)"
  type        = list(string)
  default     = null
}

variable "standards_config" {
  description = <<EOF
  `aws_foundational_security_best_practices` - AWS Foundational Security Best Practices
  `cis_aws_foundations_benchmark_v120` - CIS AWS Foundations Benchmark v1.2.0
  `cis_aws_foundations_benchmark_v140` - CIS AWS Foundations Benchmark v1.4.0
  `nist_sp_800_53_rev5` - NIST SP 800-53 Rev. 5
  `pci_dss` - PCI DSS
  EOF
  type = object({
    aws_foundational_security_best_practices = object({
      enable          = bool
      status          = optional(string)
      disabled_reason = optional(string)
    })
    cis_aws_foundations_benchmark_v120 = object({
      enable          = bool
      status          = optional(string)
      disabled_reason = optional(string)
    })
    cis_aws_foundations_benchmark_v140 = object({
      enable          = bool
      status          = optional(string)
      disabled_reason = optional(string)
    })
    nist_sp_800_53_rev5 = object({
      enable          = bool
      status          = optional(string)
      disabled_reason = optional(string)
    })
    pci_dss = object({
      enable          = bool
      status          = optional(string)
      disabled_reason = optional(string)
    })
  })
  default = {
    aws_foundational_security_best_practices = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v120 = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v140 = {
      enable = false
    }
    nist_sp_800_53_rev5 = {
      enable = false
    }
    pci_dss = {
      enable = false
    }
  }
}

variable "action_target" {
  description = <<EOF
  Creates Security Hub custom action.
  `name`        - The description for the custom action target.
  `identifier`  - The ID for the custom action target.
  `description` - The name of the custom action target.
  EOF
  type = list(object({
    name        = string
    identifier  = string
    description = string
  }))
  default = [{
    name = "Send to Amazon SNS"
    identifier = "SendToSNS"
    description = "This is a custom action to send findings to SNS Topic"
  }]
}

variable "insight_config" {
  description = <<EOF
 Provides a Security Hub custom insight resource.
 `name`     - The name of the custom insight.
 `group_by` - The attribute used to group the findings for the insight e.g., if an insight is grouped by ResourceId, then the insight produces a list of resource identifiers.
 `filters`   - A configuration block including one or more (up to 10 distinct) attributes used to filter the findings included in the insight. The insight only includes findings that match criteria defined in the filters.
 EOF
  type = list(object({
    name     = string
    group_by = string
    filters  = map(any)
  }))
  default = [{
    name     = "test"
    group_by = "AwsAccountId"
    filters = {
      aws_account_id_1 = {
        comparison = "EQUALS"
        value      = "1234567890"
      }

      aws_account_id_2 = {
        comparison = "EQUALS"
        value      = "09876543210"
      }
    }
  }]
}