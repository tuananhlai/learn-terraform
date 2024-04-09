provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "default" {

}

data "aws_ssoadmin_instances" "default" {

}

locals {
  identity_store_id = tolist(data.aws_ssoadmin_instances.default.identity_store_ids)[0]
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.default.arns)[0]
}

resource "aws_identitystore_group" "admin" {
  display_name      = "Admin"
  identity_store_id = local.identity_store_id
}

resource "aws_identitystore_user" "default" {
  name {
    given_name  = "Test"
    family_name = "User"
  }
  user_name         = "testuser"
  identity_store_id = local.identity_store_id
  display_name      = "Test User"
  emails {
    value = var.test_user_email
  }
}

resource "aws_identitystore_group_membership" "default" {
  identity_store_id = local.identity_store_id
  member_id         = aws_identitystore_user.default.user_id
  group_id          = aws_identitystore_group.admin.group_id
}

data "aws_iam_policy" "administrator_access" {
  name = "AdministratorAccess"
}

resource "aws_ssoadmin_permission_set" "default" {
  name         = "AdministratorAccess"
  instance_arn = local.sso_instance_arn
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = data.aws_iam_policy.administrator_access.arn
  permission_set_arn = aws_ssoadmin_permission_set.default.arn
}

# Assign AdministratorAccess permission of the current AWS account 
# to the "Admin" group and its members.
resource "aws_ssoadmin_account_assignment" "caller" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.default.arn
  principal_id       = aws_identitystore_group.admin.group_id
  principal_type     = "GROUP"
  target_id          = data.aws_caller_identity.default.account_id
  target_type        = "AWS_ACCOUNT"
}
