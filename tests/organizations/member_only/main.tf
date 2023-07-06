provider "aws" {
  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "member"
  alias                    = "member"
}

module "member_account" {
  source = "../../../modules/organizations_member/"

  providers = {
    aws        = aws
    aws.member = aws.member
  }

  member_config = [{
    account_id = "123456789012"
    email      = "required@example.com"
    invite     = false
  }]
}
