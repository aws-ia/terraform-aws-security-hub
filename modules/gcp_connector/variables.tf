variable "enable_inspector_vm_bridge" {
  description = "Create the Amazon Inspector VM credential bridge for every account with VM scanning: a workload identity pool `inspector-vm-bridge-<account>` with the OIDC provider `compute-engine-vm` in the management project, and a minter service account `inspector-vmscan-<account>` in each target project. The Inspector VM scanner uses it to get AWS credentials. The module owns the provider condition: it admits exactly the `target_project_ids` projects. This is opt-in so upgrading an existing deployment cannot collide with a bridge created by another onboarding workflow. Import every existing bridge resource before setting this to true. Setting it back to false destroys the bridge, and VM scanning then cannot get AWS credentials."
  type        = bool
  default     = false
  nullable    = false
}

variable "manage_audit_config" {
  description = "Create and own the organization audit configuration that the connector needs: `allServices` `DATA_WRITE` and, with Inspector, `artifactregistry.googleapis.com` `DATA_READ`. Set `false` when another configuration owns the organization audit configuration. The module then creates no audit configuration, the plan stops when a required log type is not enabled, and destroy leaves the audit configuration unchanged. In an existing deployment, run `terraform state rm` on the two `google_organization_iam_audit_config` resources before you change this to `false`, or the next apply removes them."
  type        = bool
  default     = true
  nullable    = false
}

variable "onboarded_accounts" {
  description = <<-EOF
  AWS account and Region pairs that read from this GCP organization.
  `aws_account_id`      - 12-digit AWS account ID. Names the workload identity pool and provider, the service account, the log sinks, the Cloud Asset Inventory feed and the topics.
  `aws_region`          - AWS Region of the connector, for example `us-east-1`. Names the Pub/Sub subscriptions and forms their discovery label.
  `issuer_url`          - The account's outbound identity federation issuer URL, `https://<id>.tokens.sts.global.api.aws`.
  `enable_cspm`         - Enable the CSPM pipeline. Defaults to `true`. The shared AWS Config resources are always created, so this module does not read it; accepted so every connector module takes the same list.
  `enable_inspector`    - Enable Amazon Inspector for this account and Region. Defaults to `false`. Adds Inspector federation, Cloud Functions source access, the image-pull log route and the Artifact Registry read audit log.
  `enable_inspector_vm` - With `enable_inspector` and a nonempty `target_project_ids`, trust this account's VM scanning role, grant it the OS policy orchestrator role at the organization and the VM deployer role in each target project. Defaults to `true`. Set `false` for an Inspector account that must not get VM access.
  An account can appear once per Region. Per-account resources are created once per account; Inspector is on for an account when any of its Regions enables it.
  EOF

  type = list(object({
    aws_account_id      = string
    aws_region          = string
    issuer_url          = string
    enable_cspm         = optional(bool, true)
    enable_inspector    = optional(bool, false)
    enable_inspector_vm = optional(bool, true)
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
}

variable "organization_id" {
  description = "Numeric ID of the GCP organization to onboard. The log sinks, Cloud Asset Inventory feeds, reader roles, custom roles and audit configuration are created at this organization."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id must be numeric."
  }
}

variable "permission_model" {
  description = "Read access of the connector service accounts at the organization. `broad` grants `roles/viewer` and the always-on reader roles. `granular` grants the always-on reader roles and one viewer role per supported service."
  type        = string
  default     = "broad"
  nullable    = false

  validation {
    condition     = contains(["broad", "granular"], var.permission_model)
    error_message = "permission_model must be broad or granular."
  }
}

variable "project_id" {
  description = "ID of the GCP management project. It holds the service accounts, workload identity pools, topics and subscriptions, and must be in `organization_id`. Configure it as the provider's billing project."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a 6-30 character project ID: lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "pubsub_kms_key_name" {
  description = "Optional Cloud KMS key for the lifecycle, Cloud Asset Inventory and image-pull topics, as `projects/<project>/locations/<location>/keyRings/<key ring>/cryptoKeys/<key>`. When set, the module grants the management project's Pub/Sub service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key. When `null`, the topics use Google-managed encryption."
  type        = string
  default     = null

  validation {
    condition     = var.pubsub_kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.pubsub_kms_key_name))
    error_message = "pubsub_kms_key_name must be a full Cloud KMS crypto key name: projects/<project>/locations/<location>/keyRings/<key ring>/cryptoKeys/<key>."
  }
}

variable "target_project_ids" {
  description = "Projects whose Compute Engine VMs Amazon Inspector scans. A nonempty list sets up VM scanning for every account that enables Inspector and `enable_inspector_vm`: VM scanning federation, the OS policy orchestrator role at the organization, the VM deployer role in each target project, the OS Config and Progressive Rollout service agents, and VM Manager in each project. The VM deployer role, which can set VM metadata and act as the VM service account, is granted only in these projects. Leave empty to skip VM scanning."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.target_project_ids : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", p))])
    error_message = "Every target_project_ids entry must be a 6-30 character project ID: lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }

  validation {
    condition     = length(var.target_project_ids) == length(distinct(var.target_project_ids))
    error_message = "target_project_ids contains a duplicate entry."
  }

  # VM scanning requires Inspector. A target list with no Inspector account
  # would create nothing, which looks like success.
  validation {
    condition     = length(var.target_project_ids) == 0 || anytrue([for a in var.onboarded_accounts : a.enable_inspector && a.enable_inspector_vm])
    error_message = "target_project_ids is nonempty but no onboarded account sets enable_inspector = true with enable_inspector_vm = true. VM scanning requires Amazon Inspector."
  }
}

variable "vm_orchestrator_parent" {
  description = "Where the connector service account gets the OS policy orchestrator permissions (`osconfig.policyOrchestrators.*`) for VM scanning. AWS Systems Manager creates the scanner's orchestrator under the organization for an ORGANIZATION-scope connector with no project targets, and in the management (workload identity pool) project for a connector with project targets. `organization` grants them at the organization and works for both. `project` grants them only in the management project; use it only for project-targeted connectors. If the connector later changes to ORGANIZATION scope, orchestrator creation fails until this is `organization`. The read-only VM permissions stay at the organization, and the VM write permissions stay in `target_project_ids`, for both values."
  type        = string
  default     = "organization"
  nullable    = false

  validation {
    condition     = contains(["organization", "project"], var.vm_orchestrator_parent)
    error_message = "vm_orchestrator_parent must be organization or project."
  }
}
