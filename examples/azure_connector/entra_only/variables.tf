variable "tenant_id" {
  description = "Azure tenant ID to onboard."
  type        = string
}

variable "lead_aws_account_id" {
  description = "AWS account ID used to name the shared Azure resources. Use the same value in the arm_only example."
  type        = string
}

variable "onboarded_accounts" {
  description = "AWS account and Region pairs that read from the Azure tenant. Use the same list in the arm_only example."
  type = list(object({
    aws_account_id   = string
    aws_region       = string
    issuer_url       = string
    enable_cspm      = optional(bool, true)
    enable_inspector = optional(bool, true)
    enable_threats   = optional(bool, true)
  }))
}

variable "owner_object_ids" {
  description = "Entra object IDs that own the application and service principal."
  type        = set(string)
}
