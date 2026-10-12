##################################################
# Accounts
##################################################
variable "onboarded_accounts" {
  description = <<-EOF
  AWS account and region pairs that read from this Azure tenant. Pass the same list to the `azure_connector_entra` module.
  `aws_account_id`   - 12-digit AWS account ID.
  `aws_region`       - AWS Region that reads the Azure data, for example `us-east-1`.
  `issuer_url`       - The account's outbound identity federation issuer URL. Not used by this module; accepted so both modules take the same list.
  `enable_cspm`      - Enable the CSPM pipeline (subscription Activity Log and Entra ID logs). Defaults to `true`.
  `enable_inspector` - Enable the Amazon Inspector pipeline (ACR events, VM identities, VM Run Command). Defaults to `true`.
  `enable_threats`   - Enable the threat detection pipeline (Defender for Cloud alert export). Defaults to `true`.
  Policies, diagnostic settings and role assignments are tenant-wide. They are created when any account enables the pipeline that needs them.
  EOF

  type = list(object({
    aws_account_id   = string
    aws_region       = string
    issuer_url       = string
    enable_cspm      = optional(bool, true)
    enable_inspector = optional(bool, true)
    enable_threats   = optional(bool, true)
  }))
  nullable = false

  validation {
    condition     = length(var.onboarded_accounts) > 0
    error_message = "onboarded_accounts must contain at least one entry."
  }

  validation {
    condition     = alltrue([for a in var.onboarded_accounts : can(regex("^[0-9]{12}$", a.aws_account_id))])
    error_message = "Every aws_account_id must be exactly 12 digits."
  }

  validation {
    condition     = alltrue([for a in var.onboarded_accounts : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", a.aws_region))])
    error_message = "Every aws_region must be an AWS Region code such as us-east-1."
  }

  validation {
    condition     = length(distinct([for a in var.onboarded_accounts : "${a.aws_account_id}-${a.aws_region}"])) == length(var.onboarded_accounts)
    error_message = "onboarded_accounts contains a duplicate aws_account_id and aws_region pair."
  }

  # Each pair gets a consumer group on the shared activitylog hub. The Standard
  # tier allows 20 per hub, including the built-in $Default group.
  validation {
    condition     = length(var.onboarded_accounts) <= 19
    error_message = "More than 19 account and Region pairs would exceed the Standard tier limit of 20 consumer groups per Event Hub, including $Default."
  }
}

variable "lead_aws_account_id" {
  description = "AWS account ID used to name the shared Azure resources, for example `aws-eh-<id>`. Use the same value as the `azure_connector_entra` module. Changing it renames, and therefore replaces, the Event Hub namespaces and policies."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.lead_aws_account_id))
    error_message = "lead_aws_account_id must be exactly 12 digits."
  }
}

##################################################
# Entra identity
##################################################
variable "service_principal_object_id" {
  description = "Object ID of the connector service principal, from the `service_principal_object_id` output of the `azure_connector_entra` module."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.service_principal_object_id))
    error_message = "service_principal_object_id must be an Entra object ID (GUID)."
  }
}

variable "application_client_id" {
  description = "Application (client) ID of the connector application, from the `application_client_id` output of the `azure_connector_entra` module. Used only in outputs."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_client_id))
    error_message = "application_client_id must be a GUID."
  }
}

variable "tenant_id" {
  description = "Expected Azure tenant ID. When set, the plan fails if the `azurerm` provider is authenticated to a different tenant. Pass the `tenant_id` output of the `azure_connector_entra` module."
  type        = string
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", coalesce(var.tenant_id, "-")))
    error_message = "tenant_id must be null or a tenant GUID."
  }
}

##################################################
# Event Hubs
##################################################
variable "event_hub_resource_group_name" {
  description = "Name of the resource group to create for the Event Hub namespaces, in the `azurerm` provider's subscription."
  type        = string
  default     = "aws-eventhub-rg"
  nullable    = false
}

variable "event_hub_location" {
  description = "Azure location of the shared Event Hub namespace. Also the location of the policy assignment managed identities. Changing it replaces the namespace."
  type        = string
  default     = "eastus"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.event_hub_location))
    error_message = "event_hub_location must be a canonical Azure location such as eastus."
  }
}

variable "event_hub_namespace_name" {
  description = "Name of the shared Event Hub namespace, which must be globally unique. Defaults to `aws-eh-<lead_aws_account_id>`. Regional namespaces append `-<location token>`."
  type        = string
  default     = null

  validation {
    condition     = var.event_hub_namespace_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$", coalesce(var.event_hub_namespace_name, "-")))
    error_message = "event_hub_namespace_name must be 6-50 characters, start with a letter, end with a letter or digit, and contain only letters, digits and hyphens."
  }
}

variable "azure_locations" {
  description = "Azure locations that contain container registries to scan. Each gets a regional Event Hub namespace, because ACR diagnostic settings can only send to an Event Hub in the same location. Required when any account enables Inspector."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for loc in var.azure_locations : can(regex("^[a-z0-9]+$", loc))])
    error_message = "azure_locations must use canonical Azure location names, such as eastus (not \"East US\")."
  }

  validation {
    condition     = length(distinct(var.azure_locations)) == length(var.azure_locations)
    error_message = "azure_locations contains duplicate entries."
  }

  validation {
    condition     = !anytrue([for a in var.onboarded_accounts : a.enable_inspector]) || length(var.azure_locations) > 0
    error_message = "An account enables Inspector, which requires at least one entry in azure_locations."
  }
}

variable "azure_location_tokens" {
  description = "Overrides for the short location token used in regional resource names, keyed by Azure location. Locations without an override use a built-in token or the first 6 characters of the location's MD5 hash."
  type        = map(string)
  default     = {}
  nullable    = false

  # The token is appended to ACRDiagToEH-<4 digits>-, and a management group
  # policy assignment name is limited to 24 characters.
  validation {
    condition     = alltrue([for v in values(var.azure_location_tokens) : can(regex("^[a-z0-9]{1,7}$", v))])
    error_message = "Each azure_location_tokens value must be 1-7 lowercase letters or digits."
  }

  validation {
    condition     = alltrue([for loc in keys(var.azure_location_tokens) : contains(var.azure_locations, loc)])
    error_message = "azure_location_tokens contains a location that is not in azure_locations."
  }
}

variable "tags" {
  description = "Tags for the resource group and Event Hub namespaces. The module also adds, to the namespaces, the discovery tags the connector uses to find the Event Hubs."
  type        = map(string)
  default     = {}
  nullable    = false

  # A resource holds at most 50 tags. The shared namespace carries one AWSConfig
  # tag per pair and one AWSSecurityHub tag per threats-enabled pair.
  validation {
    condition = (
      length(var.tags) + length(var.onboarded_accounts) + length([for a in var.onboarded_accounts : a if a.enable_threats])
    ) <= 50
    error_message = "The shared Event Hub namespace would carry more than 50 tags. Reduce var.tags."
  }
}

##################################################
# Provider registration and remediation
##################################################
variable "register_resource_providers" {
  description = "Register the Microsoft.Insights, Microsoft.EventHub and Microsoft.PolicyInsights resource providers (and Microsoft.Security when threats are enabled) in every subscription in `remediation_subscription_ids`, and Microsoft.PolicyInsights on the tenant root management group when `create_policy_remediations` is true. Registration is requested but not awaited."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_policy_remediations" {
  description = "Scan subscriptions for compliance and create one policy remediation task per policy assignment at the tenant root management group, so the policies also configure resources that existed before the assignments. Without them the policies only act on resources created or updated afterwards."
  type        = bool
  default     = true
  nullable    = false
}

variable "compliance_scan_timeout" {
  description = "How long to wait for the compliance scan of each subscription before remediation, as a Terraform duration such as `60m`. A subscription with many resources takes longer to scan."
  type        = string
  default     = "60m"
  nullable    = false

  validation {
    condition     = can(regex("^([0-9]+h)?([0-9]+m)?([0-9]+s)?$", var.compliance_scan_timeout)) && var.compliance_scan_timeout != ""
    error_message = "compliance_scan_timeout must be a duration such as 60m, 2h or 1h30m."
  }
}

variable "remediation_resource_count" {
  description = "Maximum number of non-compliant resources each remediation task fixes. Azure's default is 500 and its maximum is 50,000. Raise it for a tenant with more resources per policy than that."
  type        = number
  default     = 500
  nullable    = false

  validation {
    condition     = var.remediation_resource_count == floor(var.remediation_resource_count) && var.remediation_resource_count >= 1 && var.remediation_resource_count <= 50000
    error_message = "remediation_resource_count must be a whole number from 1 to 50000."
  }
}

variable "remediation_subscription_ids" {
  description = "Subscriptions to register resource providers in and scan for compliance before remediation. Defaults to every enabled subscription in the tenant that the `azurerm` identity can read. The remediation tasks cover every subscription under the tenant root management group; a subscription left out is not scanned, so only resources Azure has already evaluated there are fixed."
  type        = list(string)
  default     = null

  validation {
    condition = var.remediation_subscription_ids == null || alltrue([
      for id in coalesce(var.remediation_subscription_ids, []) : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every remediation_subscription_ids entry must be a subscription GUID."
  }
}
