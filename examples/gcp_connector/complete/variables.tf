variable "organization_id" {
  description = "Numeric ID of the GCP organization to onboard."
  type        = string
}

variable "project_id" {
  description = "GCP management project that holds the connector resources."
  type        = string
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

variable "target_project_ids" {
  description = "Projects whose Compute Engine VMs Amazon Inspector scans. Leave empty to skip VM scanning."
  type        = list(string)
  default     = []
}
