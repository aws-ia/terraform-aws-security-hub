data "azuread_client_config" "current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  tenant_id = data.azuread_client_config.current.tenant_id
  app_name  = coalesce(var.app_name, "AWSAuthApp-${var.lead_aws_account_id}")

  # Federated credentials are per AWS account, not per account and Region: the
  # subjects contain no Region. A pipeline is on for an account when any of its
  # Regions enables it.
  account_ids = distinct([for a in var.onboarded_accounts : a.aws_account_id])
  accounts = {
    for id in local.account_ids : id => {
      issuer_url       = [for a in var.onboarded_accounts : a.issuer_url if a.aws_account_id == id][0]
      enable_inspector = anytrue([for a in var.onboarded_accounts : a.enable_inspector if a.aws_account_id == id])
      enable_threats   = anytrue([for a in var.onboarded_accounts : a.enable_threats if a.aws_account_id == id])
    }
  }

  # Subjects are the AWS roles that request Azure tokens. Keys are static so
  # for_each addresses stay stable when accounts are added or removed.
  federated_credentials = merge([
    for id, a in local.accounts : merge(
      {
        "${id}-config-slr" = {
          account = id
          issuer  = a.issuer_url
          subject = "arn:aws:iam::${id}:role/aws-service-role/thirdparty.config.amazonaws.com/AWSServiceRoleForConfigThirdParty"
        }
      },
      a.enable_inspector ? {
        "${id}-inspector-slr" = {
          account = id
          issuer  = a.issuer_url
          subject = "arn:aws:iam::${id}:role/aws-service-role/thirdparty.inspector2.amazonaws.com/AWSServiceRoleForAmazonInspector2ThirdParty"
        }
        "${id}-inspector-ssm" = {
          account = id
          issuer  = a.issuer_url
          subject = "arn:aws:iam::${id}:role/Inspector2SSMFederationRole-${local.tenant_id}"
        }
      } : {},
      a.enable_threats ? {
        "${id}-securityhub-v2-slr" = {
          account = id
          issuer  = a.issuer_url
          subject = "arn:aws:iam::${id}:role/aws-service-role/securityhubv2.amazonaws.com/AWSServiceRoleForSecurityHubV2"
        }
      } : {},
    )
  ]...)

  # Read-only Microsoft Graph application permissions the connector uses. Role
  # IDs are looked up from the tenant's Microsoft Graph service principal.
  graph_application_permissions = toset([
    "Application.Read.All",
    "AuditLog.Read.All",
    "DelegatedPermissionGrant.Read.All",
    "Device.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All",
    "GroupSettings.Read.All",
    "Organization.Read.All",
    "Policy.Read.All",
    "RoleManagement.Read.Directory",
    "User.Read.All",
    "UserAuthenticationMethod.Read.All",
  ])

  owners = sort([for id in var.owner_object_ids : lower(id)])
}

##################################################
# Application registration and service principal
##################################################
resource "azuread_application" "connector" {
  display_name            = local.app_name
  sign_in_audience        = "AzureADMyOrg"
  owners                  = local.owners
  prevent_duplicate_names = true

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    dynamic "resource_access" {
      for_each = local.graph_application_permissions
      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }

  lifecycle {
    # azuread_application_identifier_uri.connector owns this attribute.
    ignore_changes = [identifier_uris]
  }
}

# api://<client id>. A separate resource because the URI contains the client ID
# that the application generates.
resource "azuread_application_identifier_uri" "connector" {
  application_id = azuread_application.connector.id
  identifier_uri = "api://${azuread_application.connector.client_id}"
}

resource "azuread_service_principal" "connector" {
  client_id                    = azuread_application.connector.client_id
  app_role_assignment_required = false
  owners                       = local.owners
}

##################################################
# Federated identity credentials (AWS to Entra)
##################################################
resource "azuread_application_federated_identity_credential" "aws" {
  #checkov:skip=CKV_AZURE_249:This check is for GitHub Actions issuers. These credentials trust an AWS outbound identity federation issuer and an exact IAM role subject.
  for_each = local.federated_credentials

  application_id = azuread_application.connector.id
  display_name   = "aws-${md5(each.value.subject)}"
  description    = "AWS federation for account ${each.value.account}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = each.value.issuer
  subject        = each.value.subject
}

##################################################
# Microsoft Graph admin consent
##################################################
# An app role assignment on the Microsoft Graph service principal grants admin
# consent for that application permission. The identity running Terraform needs
# Global Administrator or Privileged Role Administrator.
resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_application_permissions

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.connector.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
