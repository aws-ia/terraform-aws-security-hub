# GCP connector: complete

Onboards a GCP organization for AWS Config and Amazon Inspector, including Compute Engine VM scanning and the VM credential bridge, in one Terraform state. This example turns Amazon Inspector on for every entry unless the entry sets `enable_inspector = false`; the module's own default is `false`. The identity that runs it needs the permissions of the [`gcp_connector`](../../../modules/gcp\_connector) module. Applying with `target_project_ids` also needs the `gcloud` CLI on `PATH`. Set `pubsub_kms_key_name` to encrypt the connector topics with your own Cloud KMS key, and `manage_audit_config = false` when another configuration owns the organization audit configuration.

```shell
gcloud auth application-default login
terraform init
terraform apply \
  -var organization_id=<organization id> \
  -var project_id=<management project id> \
  -var 'target_project_ids=["<vm project id>"]' \
  -var 'onboarded_accounts=[{aws_account_id="123456789012",aws_region="us-east-1",issuer_url="https://<id>.tokens.sts.global.api.aws"}]'
```

Use `per_account_connector_inputs` from the outputs when you create the connector in AWS. `inspector_vm_bridge` shows the bridge audience and the minter email of each target project.

### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.50 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 7.27 |

### Providers

No providers.

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_gcp_connector"></a> [gcp\_connector](#module\_gcp\_connector) | ../../../modules/gcp_connector | n/a |

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from the GCP organization. See the module documentation for the object attributes. | <pre>list(object({<br/>    aws_account_id      = string<br/>    aws_region          = string<br/>    issuer_url          = string<br/>    enable_cspm         = optional(bool, true)<br/>    enable_inspector    = optional(bool, true)<br/>    enable_inspector_vm = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Numeric ID of the GCP organization to onboard. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP management project that holds the connector resources. | `string` | n/a | yes |
| <a name="input_enable_inspector_vm_bridge"></a> [enable\_inspector\_vm\_bridge](#input\_enable\_inspector\_vm\_bridge) | Create the Amazon Inspector VM credential bridge for accounts with VM scanning. Import an existing script-created bridge before enabling it. Setting false destroys a bridge already managed by this state. | `bool` | `false` | no |
| <a name="input_manage_audit_config"></a> [manage\_audit\_config](#input\_manage\_audit\_config) | Create and own the organization audit configuration. Set false when another configuration owns it. | `bool` | `true` | no |
| <a name="input_pubsub_kms_key_name"></a> [pubsub\_kms\_key\_name](#input\_pubsub\_kms\_key\_name) | Optional Cloud KMS key for the connector topics. Null uses Google-managed encryption. | `string` | `null` | no |
| <a name="input_target_project_ids"></a> [target\_project\_ids](#input\_target\_project\_ids) | Projects whose Compute Engine VMs Amazon Inspector scans. Leave empty to skip VM scanning. | `list(string)` | `[]` | no |
| <a name="input_vm_orchestrator_parent"></a> [vm\_orchestrator\_parent](#input\_vm\_orchestrator\_parent) | Where the connector gets the OS policy orchestrator permissions: organization (any connector scope) or project (project-targeted connectors only). See the module documentation. | `string` | `"organization"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_accounts"></a> [accounts](#output\_accounts) | Service account, workload identity provider and audience, topics and sink writer identities of each AWS account. |
| <a name="output_custom_roles"></a> [custom\_roles](#output\_custom\_roles) | Custom roles that the module creates. |
| <a name="output_inspector_vm_bridge"></a> [inspector\_vm\_bridge](#output\_inspector\_vm\_bridge) | Amazon Inspector VM credential bridge pool, provider, audience and minter emails of each account with VM scanning. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Connector inputs for each onboarded account and Region. |
| <a name="output_service_agents"></a> [service\_agents](#output\_service\_agents) | Google-managed service agents that the module creates or grants roles to. |
