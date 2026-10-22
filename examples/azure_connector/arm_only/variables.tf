variable "tenant_id" {
  description = "Azure tenant ID, from the entra_only example."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription that hosts the Event Hub namespaces."
  type        = string
}

variable "service_principal_object_id" {
  description = "Service principal object ID, from the entra_only example."
  type        = string
}

variable "application_client_id" {
  description = "Application (client) ID, from the entra_only example."
  type        = string
}

variable "lead_aws_account_id" {
  description = "AWS account ID used to name the shared Azure resources. Use the same value as the entra_only example."
  type        = string
}

variable "onboarded_accounts" {
  description = "AWS account and Region pairs that read from the Azure tenant. Use the same list as the entra_only example."
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
  default     = []
}
