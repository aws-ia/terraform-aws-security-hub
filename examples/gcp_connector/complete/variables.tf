variable "manage_audit_config" {
  description = "Create and own the organization audit configuration. Set false when another configuration owns it."
  type        = bool
  default     = true
}

variable "onboarded_accounts" {
  description = "AWS account and Region pairs that read from the GCP organization. See the module documentation for the object attributes."
  type = list(object({
    aws_account_id      = string
    aws_region          = string
    issuer_url          = string
    enable_cspm         = optional(bool, true)
    enable_inspector    = optional(bool, true)
    enable_inspector_vm = optional(bool, true)
  }))
}

variable "organization_id" {
  description = "Numeric ID of the GCP organization to onboard."
  type        = string
}

variable "project_id" {
  description = "GCP management project that holds the connector resources."
  type        = string
}

variable "pubsub_kms_key_name" {
  description = "Optional Cloud KMS key for the connector topics. Null uses Google-managed encryption."
  type        = string
  default     = null
}

variable "target_project_ids" {
  description = "Projects whose Compute Engine VMs Amazon Inspector scans. Leave empty to skip VM scanning."
  type        = list(string)
  default     = []
}
