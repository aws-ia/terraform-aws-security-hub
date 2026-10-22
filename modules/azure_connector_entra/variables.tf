##################################################
# Accounts
##################################################
variable "onboarded_accounts" {
  description = <<-EOF
  AWS account and region pairs that read from this Azure tenant. Pass the same list to the `azure_connector_arm` module.
  `aws_account_id`   - 12-digit AWS account ID.
  `aws_region`       - AWS Region that reads the Azure data, for example `us-east-1`.
  `issuer_url`       - The account's outbound identity federation issuer URL, `https://<id>.tokens.sts.global.api.aws`.
  `enable_cspm`      - Enable the CSPM pipeline. Defaults to `true`. Not used by this module; accepted so both modules take the same list.
  `enable_inspector` - Create the federated credentials for Amazon Inspector. Defaults to `true`.
  `enable_threats`   - Create the federated credential for Security Hub threat detection. Defaults to `true`.
  An account can appear once per Region. Federated credentials are created once per account, and every account gets the AWS Config credential.
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
    condition = alltrue([
      for a in var.onboarded_accounts :
      can(regex("^https://[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\.tokens\\.sts\\.global\\.api\\.aws$", a.issuer_url))
    ])
    error_message = "Every issuer_url must be https://<UUID>.tokens.sts.global.api.aws with no path, port or query."
  }

  validation {
    condition     = length(distinct([for a in var.onboarded_accounts : "${a.aws_account_id}-${a.aws_region}"])) == length(var.onboarded_accounts)
    error_message = "onboarded_accounts contains a duplicate aws_account_id and aws_region pair."
  }

  validation {
    condition = alltrue([
      for id in distinct([for a in var.onboarded_accounts : a.aws_account_id]) :
      length(distinct([for a in var.onboarded_accounts : a.issuer_url if a.aws_account_id == id])) == 1
    ])
    error_message = "An aws_account_id appears with more than one issuer_url. Each AWS account has one issuer."
  }

  # Entra allows 20 federated identity credentials per application. Each account
  # uses 1 (CSPM only), 3 (with Inspector) or 4 (Inspector and threats).
  validation {
    condition = length(flatten([
      for id in distinct([for a in var.onboarded_accounts : a.aws_account_id]) : concat(
        ["config"],
        anytrue([for a in var.onboarded_accounts : a.enable_inspector if a.aws_account_id == id]) ? ["inspector-slr", "inspector-ssm"] : [],
        anytrue([for a in var.onboarded_accounts : a.enable_threats if a.aws_account_id == id]) ? ["securityhub"] : [],
      )
    ])) <= 20
    error_message = "This configuration needs more than 20 federated identity credentials, which is the Entra limit per application. Split the accounts across deployments with different lead_aws_account_id values."
  }
}

variable "lead_aws_account_id" {
  description = "AWS account ID used to name the shared Azure resources, for example `AWSAuthApp-<id>`. It does not need to be in `onboarded_accounts`. Changing it renames the application."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.lead_aws_account_id))
    error_message = "lead_aws_account_id must be exactly 12 digits."
  }
}

##################################################
# Application
##################################################
variable "app_name" {
  description = "Display name of the Entra application registration. Defaults to `AWSAuthApp-<lead_aws_account_id>`."
  type        = string
  default     = null
}

variable "owner_object_ids" {
  description = "Entra object IDs that own the application and service principal. Terraform manages this set, so include every owner you want to keep, and keep it the same when a different identity runs Terraform."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.owner_object_ids) > 0
    error_message = "owner_object_ids must contain at least one Entra object ID."
  }

  validation {
    condition = alltrue([
      for id in var.owner_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every owner_object_ids entry must be an Entra object ID (GUID)."
  }
}
