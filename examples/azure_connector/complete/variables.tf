variable "tenant_id" {
  description = "Azure tenant ID to onboard."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription that hosts the Event Hub namespaces."
  type        = string
}

variable "owner_object_ids" {
  description = "Entra object IDs that own the application and service principal."
  type        = set(string)
}

variable "lead_aws_account_id" {
  description = "AWS account ID used to name the shared Azure resources."
  type        = string
}

variable "onboarded_accounts" {
  description = "AWS account and Region pairs that read from the Azure tenant. See the module documentation for the object attributes."
  type = list(object({
    aws_account_id   = string
    aws_region       = string
    issuer_url       = string
    enable_cspm      = optional(bool, true)
    enable_inspector = optional(bool, true)
    enable_threats   = optional(bool, true)
  }))
}

variable "azure_locations" {
  description = "Azure locations that contain container registries for Amazon Inspector to scan."
  type        = list(string)
  default     = ["eastus"]
}
