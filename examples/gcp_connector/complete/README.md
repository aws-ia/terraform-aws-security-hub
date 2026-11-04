# GCP connector: complete

Onboards a GCP organization for AWS Config and Amazon Inspector, including Compute Engine VM scanning, in one Terraform state. Amazon Inspector is on for every entry unless the entry sets `enable_inspector = false`. The identity that runs it needs the permissions of the [`gcp_connector`](../../../modules/gcp\_connector) module. Applying with `target_project_ids` also needs the `gcloud` CLI with the beta component on `PATH`.

```shell
gcloud auth application-default login
terraform init
terraform apply \
  -var organization_id=<organization id> \
  -var project_id=<management project id> \
  -var 'target_project_ids=["<vm project id>"]' \
  -var 'onboarded_accounts=[{aws_account_id="123456789012",aws_region="us-east-1",issuer_url="https://<id>.tokens.sts.global.api.aws"}]'
```

Use `per_account_connector_inputs` from the outputs when you create the connector in AWS.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.50 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 6.50 |

### Providers

No providers.

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gcp_connector"></a> [gcp\_connector](#module\_gcp\_connector) | ../../../modules/gcp_connector | n/a |

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_onboarded_accounts"></a> [onboarded\_accounts](#input\_onboarded\_accounts) | AWS account and Region pairs that read from the GCP organization. See the module documentation for the object attributes. | <pre>list(object({<br/>    aws_account_id      = string<br/>    aws_region          = string<br/>    issuer_url          = string<br/>    enable_cspm         = optional(bool, true)<br/>    enable_inspector    = optional(bool, true)<br/>    enable_inspector_vm = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Numeric ID of the GCP organization to onboard. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP management project that holds the connector resources. | `string` | n/a | yes |
| <a name="input_target_project_ids"></a> [target\_project\_ids](#input\_target\_project\_ids) | Projects whose Compute Engine VMs Amazon Inspector scans. Leave empty to skip VM scanning. | `list(string)` | `[]` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_accounts"></a> [accounts](#output\_accounts) | Service account and workload identity provider of each AWS account. |
| <a name="output_per_account_connector_inputs"></a> [per\_account\_connector\_inputs](#output\_per\_account\_connector\_inputs) | Connector inputs for each onboarded account and Region. |
