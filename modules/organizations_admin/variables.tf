variable "admin_account_id" {
  description = "AWS Organizations Admin Account Id. Defaults to `null`"
  type        = string
  default     = null
}

variable "auto_enable_standards" {
  description = "Automatically enable Security Hub default standards for new member accounts in the organization. To opt-out of enabling default standards, set to `NONE`. Defaults to `DEFAULT`."
  type        = string
  default     = "DEFAULT"
}