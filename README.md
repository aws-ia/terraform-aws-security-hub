# Terraform Module for AWS Security Hub

Terraform module that creates AWS Security Hub resources.

- [Terraform Module for AWS Security Hub](#terraform-module-for-aws-security-hub)
  - [Usage](#usage)
    - [Standalone](#standalone)
    - [Organizations](#organizations)
  - [Overview Diagrams](#overview-diagrams)
    - [Standalone](#standalone-1)
    - [Organizations](#organizations-1)
  - [Terraform Module](#terraform-module)

## Usage

### Standalone

```hcl
module "security_hub" {
  source = "../../../"

  enable_default_standards  = false
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = true

  product_config = [{
    enable = true
    arn    = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  }]

  standards_config = {
    aws_foundational_security_best_practices = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v120 = {
      enable = false
    }
    cis_aws_foundations_benchmark_v140 = {
      enable = true
      status = "ENABLED"
    }
    nist_sp_800_53_rev5 = {
      enable = false
    }
    pci_dss = {
      enable = false
    }
  }

  action_target = [{
    name        = "Send to Amazon SNS"
    identifier  = "SendToSNS"
    description = "This is a custom action to send findings to SNS Topic"
  }]

}

resource "aws_securityhub_standards_control" "ensure_iam_password_policy_prevents_password_reuse" {
  standards_control_arn = "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:control/cis-aws-foundations-benchmark/v/1.4.0/1.10"
  control_status        = "DISABLED"
  disabled_reason       = "Password policies are managed by external resource"

  depends_on = [module.security_hub]
}

resource "aws_securityhub_insight" "this" {
  filters {
    created_at {
      date_range {
        unit  = "DAYS"
        value = 7
      }
    }
    network_source_ipv4 {
      cidr = "10.0.0.0/16"
    }
    criticality {
      gte = "80"
    }
    resource_tags {
      comparison = "EQUALS"
      key        = "Environment"
      value      = "Development"
    }
  }

  group_by_attribute = "AwsAccountId"

  name = "insight"

  depends_on = [module.standalone_security_hub]
}
```

### Organizations

```hcl
module "delegated_admin" {
  source = "aws-ia/terraform-aws-security-hub/aws//modules/organizations_admin/"

  admin_account_id      = data.aws_caller_identity.current.account_id
  auto_enable_standards = "DEFAULT"

  depends_on = [module.security_hub]
}

module "member_account" {
  source = "aws-ia/terraform-aws-security-hub/aws//modules/organizations_member/"

  providers = {
    aws        = aws
    aws.member = aws.member
  }

  member_config = [{
    account_id = "281190191734"
    email      = "required@example.com"
    invite     = false
  }]

  depends_on = [module.security_hub]
}

module "security_hub" {
  source = "aws-ia/terraform-aws-security-hub"

  enable_default_standards  = false
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = true

  product_config = [{
    enable = true
    arn    = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  }]

  standards_config = {
    aws_foundational_security_best_practices = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v120 = {
      enable = false
    }
    cis_aws_foundations_benchmark_v140 = {
      enable = true
      status = "ENABLED"
    }
    nist_sp_800_53_rev5 = {
      enable = false
    }
    pci_dss = {
      enable = false
    }
  }

  action_target = [{
    name        = "Send to Amazon SNS"
    identifier  = "SendToSNS"
    description = "This is a custom action to send findings to SNS Topic"
  }]
}

resource "aws_securityhub_insight" "this" {
  filters {
    aws_account_id {
      comparison = "EQUALS"
      value      = "123456789012"
    }
    aws_account_id {
      comparison = "EQUALS"
      value      = "098765432109"
    }
    created_at {
      date_range {
        unit  = "DAYS"
        value = 7
      }
    }
    network_source_ipv4 {
      cidr = "10.0.0.0/16"
    }
    criticality {
      gte = "80"
    }
    resource_tags {
      comparison = "EQUALS"
      key        = "Environment"
      value      = "Development"
    }
  }

  group_by_attribute = "AwsAccountId"

  name = "insight-per-account-id"

  depends_on = [module.security_hub]
}
```

## Overview Diagrams

### Standalone

![standalone-diagram](./docs/Architectures-SecurityHub\_Standalone.png)

### Organizations

![organizations-diagram](./docs/Architectures-SecurityHub\_Org.png)

## Terraform Module

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.47 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.9 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.47 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.9 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [aws_securityhub_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_action_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_action_target) | resource |
| [aws_securityhub_finding_aggregator.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_finding_aggregator) | resource |
| [aws_securityhub_product_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_product_subscription) | resource |
| [aws_securityhub_standards_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_subscription) | resource |
| [time_sleep.wait_securityhub_enable](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_action_target"></a> [action\_target](#input\_action\_target) | Creates Security Hub custom action.<br>  `name`        - The description for the custom action target.<br>  `identifier`  - The ID for the custom action target.<br>  `description` - The name of the custom action target. | <pre>list(object({<br>    name        = string<br>    identifier  = string<br>    description = string<br>  }))</pre> | `[]` | no |
| <a name="input_auto_enable_controls"></a> [auto\_enable\_controls](#input\_auto\_enable\_controls) | Whether to automatically enable new controls when they are added to standards that are enabled. By default, this is set to true, and new controls are enabled automatically. To not automatically enable new controls, set this to false. | `bool` | `true` | no |
| <a name="input_control_finding_generator"></a> [control\_finding\_generator](#input\_control\_finding\_generator) | Updates whether the calling account has consolidated control findings turned on. If the value for this field is set to SECURITY\_CONTROL, Security Hub generates a single finding for a control check even when the check applies to multiple enabled standards. If the value for this field is set to STANDARD\_CONTROL, Security Hub generates separate findings for a control check when the check applies to multiple enabled standards. For accounts that are part of an organization, this value can only be updated in the administrator account. | `string` | `"STANDARD_CONTROL"` | no |
| <a name="input_enable_default_standards"></a> [enable\_default\_standards](#input\_enable\_default\_standards) | Whether to enable the security standards that Security Hub has designated as automatically enabled including: AWS Foundational Security Best Practices v1.0.0 and CIS AWS Foundations Benchmark v1.2.0. Defaults to `true`. | `bool` | `true` | no |
| <a name="input_linking_mode"></a> [linking\_mode](#input\_linking\_mode) | Indicates whether to aggregate findings from all of the available Regions or from a specified list. The options are ALL\_REGIONS, ALL\_REGIONS\_EXCEPT\_SPECIFIED or SPECIFIED\_REGIONS. When ALL\_REGIONS or ALL\_REGIONS\_EXCEPT\_SPECIFIED are used, Security Hub will automatically aggregate findings from new Regions as Security Hub supports them and you opt into them. | `string` | `"ALL_REGIONS"` | no |
| <a name="input_product_config"></a> [product\_config](#input\_product\_config) | The ARN of the product that generates findings that you want to import into Security Hub. | <pre>list(object({<br>    enable = bool<br>    arn    = string<br>  }))</pre> | `null` | no |
| <a name="input_specified_regions"></a> [specified\_regions](#input\_specified\_regions) | List of regions to include or exclude (required if linking\_mode is set to ALL\_REGIONS\_EXCEPT\_SPECIFIED or SPECIFIED\_REGIONS) | `list(string)` | `null` | no |
| <a name="input_standards_config"></a> [standards\_config](#input\_standards\_config) | `aws_foundational_security_best_practices` - AWS Foundational Security Best Practices<br>  `cis_aws_foundations_benchmark_v120` - CIS AWS Foundations Benchmark v1.2.0<br>  `cis_aws_foundations_benchmark_v140` - CIS AWS Foundations Benchmark v1.4.0<br>  `nist_sp_800_53_rev5` - NIST SP 800-53 Rev. 5<br>  `pci_dss` - PCI DSS | <pre>object({<br>    aws_foundational_security_best_practices = object({<br>      enable          = bool<br>      status          = optional(string)<br>      disabled_reason = optional(string)<br>    })<br>    cis_aws_foundations_benchmark_v120 = object({<br>      enable          = bool<br>      status          = optional(string)<br>      disabled_reason = optional(string)<br>    })<br>    cis_aws_foundations_benchmark_v140 = object({<br>      enable          = bool<br>      status          = optional(string)<br>      disabled_reason = optional(string)<br>    })<br>    nist_sp_800_53_rev5 = object({<br>      enable          = bool<br>      status          = optional(string)<br>      disabled_reason = optional(string)<br>    })<br>    pci_dss = object({<br>      enable          = bool<br>      status          = optional(string)<br>      disabled_reason = optional(string)<br>    })<br>  })</pre> | <pre>{<br>  "aws_foundational_security_best_practices": {<br>    "enable": true,<br>    "status": "ENABLED"<br>  },<br>  "cis_aws_foundations_benchmark_v120": {<br>    "enable": true,<br>    "status": "ENABLED"<br>  },<br>  "cis_aws_foundations_benchmark_v140": {<br>    "enable": false<br>  },<br>  "nist_sp_800_53_rev5": {<br>    "enable": false<br>  },<br>  "pci_dss": {<br>    "enable": false<br>  }<br>}</pre> | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_action_target"></a> [action\_target](#output\_action\_target) | Security Hub custome action targets. |
| <a name="output_finding_aggregator"></a> [finding\_aggregator](#output\_finding\_aggregator) | Security Hub finding aggregator configuration. |
| <a name="output_product_subscription"></a> [product\_subscription](#output\_product\_subscription) | Security Hub products subscriptions. |
| <a name="output_securityhub_account"></a> [securityhub\_account](#output\_securityhub\_account) | Security Hub AWS account configuration. |
| <a name="output_standards_subscription"></a> [standards\_subscription](#output\_standards\_subscription) | Security Hub compliance standards subscriptions. |
