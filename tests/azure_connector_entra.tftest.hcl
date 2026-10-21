mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  mock_data "azuread_application_published_app_ids" {
    defaults = {
      result = {
        MicrosoftGraph = "00000003-0000-0000-c000-000000000000"
      }
    }
  }

  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "33333333-3333-3333-3333-333333333333"
      app_role_ids = {
        "Application.Read.All"              = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"
        "AuditLog.Read.All"                 = "b0afded3-3588-46d8-8b3d-9842eff778da"
        "DelegatedPermissionGrant.Read.All" = "81b4724a-58aa-41c1-8a55-84ef97466587"
        "Device.Read.All"                   = "7438b122-aefc-4978-80ed-43db9fcc7715"
        "Group.Read.All"                    = "5b567255-7703-4780-807c-7be8301ae99b"
        "GroupMember.Read.All"              = "98830695-27a2-44f7-8c18-0c3ebc9698f6"
        "GroupSettings.Read.All"            = "c6292d16-2dbe-4cb6-8f3c-63a7a3d4ac1c"
        "Organization.Read.All"             = "498476ce-e0fe-48b0-b801-37ba7e2685c6"
        "Policy.Read.All"                   = "246dd0d5-5bd0-4def-940b-0421030a5b68"
        "RoleManagement.Read.Directory"     = "483bed4a-2ad3-4361-a73b-c83ccdbdc53c"
        "User.Read.All"                     = "df021288-bdef-4463-88db-98f22de89214"
        "UserAuthenticationMethod.Read.All" = "38d9df27-64da-44fd-b7c5-a6fbac20248f"
      }
    }
  }
}

variables {
  lead_aws_account_id = "123456789012"
  owner_object_ids    = ["44444444-4444-4444-4444-444444444444"]
  onboarded_accounts = [
    {
      aws_account_id = "123456789012"
      aws_region     = "us-east-1"
      issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
    },
  ]
}

run "all_pipelines" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  assert {
    condition     = azuread_application.connector.display_name == "AWSAuthApp-123456789012"
    error_message = "The default application name must be AWSAuthApp-<lead account>."
  }

  assert {
    condition = toset(keys(azuread_application_federated_identity_credential.aws)) == toset([
      "123456789012-config-slr",
      "123456789012-inspector-slr",
      "123456789012-inspector-ssm",
      "123456789012-securityhub-v2-slr",
    ])
    error_message = "An account with every pipeline needs four federated credentials."
  }

  assert {
    condition = {
      for k, c in azuread_application_federated_identity_credential.aws : k => c.subject
      } == {
      "123456789012-config-slr"         = "arn:aws:iam::123456789012:role/aws-service-role/thirdparty.config.amazonaws.com/AWSServiceRoleForConfigThirdParty"
      "123456789012-inspector-slr"      = "arn:aws:iam::123456789012:role/aws-service-role/thirdparty.inspector2.amazonaws.com/AWSServiceRoleForAmazonInspector2ThirdParty"
      "123456789012-inspector-ssm"      = "arn:aws:iam::123456789012:role/Inspector2SSMFederationRole-11111111-1111-1111-1111-111111111111"
      "123456789012-securityhub-v2-slr" = "arn:aws:iam::123456789012:role/aws-service-role/securityhubv2.amazonaws.com/AWSServiceRoleForSecurityHubV2"
    }
    error_message = "Each federated credential must trust the exact IAM role subject for its pipeline. The Inspector SSM subject contains the tenant ID."
  }

  assert {
    condition     = alltrue([for c in azuread_application_federated_identity_credential.aws : length(c.audiences) == 1 && contains(c.audiences, "api://AzureADTokenExchange")])
    error_message = "Every federated credential must use the api://AzureADTokenExchange audience."
  }

  assert {
    condition     = length(azuread_app_role_assignment.graph) == 12
    error_message = "All twelve Microsoft Graph permissions must be granted."
  }

  assert {
    condition     = azuread_application.connector.owners == toset(["44444444-4444-4444-4444-444444444444"])
    error_message = "owner_object_ids must set the application owners."
  }
}

run "config_only_account" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    onboarded_accounts = [
      {
        aws_account_id   = "123456789012"
        aws_region       = "us-east-1"
        issuer_url       = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
        enable_inspector = false
        enable_threats   = false
      },
    ]
  }

  assert {
    condition     = keys(azuread_application_federated_identity_credential.aws) == ["123456789012-config-slr"]
    error_message = "A CSPM-only account needs only the AWS Config credential."
  }
}

run "one_account_two_regions" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    app_name = "custom-connector"
    onboarded_accounts = [
      {
        aws_account_id = "123456789012"
        aws_region     = "us-east-1"
        issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
        enable_threats = false
      },
      {
        aws_account_id   = "123456789012"
        aws_region       = "eu-west-1"
        issuer_url       = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
        enable_inspector = false
      },
    ]
  }

  assert {
    condition     = length(azuread_application_federated_identity_credential.aws) == 4
    error_message = "Credentials are per account: a pipeline enabled in any Region creates its credentials once."
  }

  assert {
    condition     = azuread_application.connector.display_name == "custom-connector"
    error_message = "app_name must override the default name."
  }

  assert {
    condition     = azuread_service_principal.connector.owners == toset(["44444444-4444-4444-4444-444444444444"])
    error_message = "owner_object_ids must set the service principal owners."
  }
}

run "rejects_empty_owners" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    owner_object_ids = []
  }

  expect_failures = [var.owner_object_ids]
}

run "rejects_invalid_account_id" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    onboarded_accounts = [
      {
        aws_account_id = "1234"
        aws_region     = "us-east-1"
        issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
      },
    ]
  }

  expect_failures = [var.onboarded_accounts]
}

run "rejects_conflicting_issuers" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    onboarded_accounts = [
      {
        aws_account_id = "123456789012"
        aws_region     = "us-east-1"
        issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
      },
      {
        aws_account_id = "123456789012"
        aws_region     = "us-west-2"
        issuer_url     = "https://ffffffff-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
      },
    ]
  }

  expect_failures = [var.onboarded_accounts]
}

run "rejects_more_than_twenty_credentials" {
  module {
    source = "./modules/azure_connector_entra"
  }

  command = plan

  variables {
    onboarded_accounts = [
      for i in range(6) : {
        aws_account_id = format("1000000000%02d", i)
        aws_region     = "us-east-1"
        issuer_url     = "https://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.tokens.sts.global.api.aws"
      }
    ]
  }

  expect_failures = [var.onboarded_accounts]
}
