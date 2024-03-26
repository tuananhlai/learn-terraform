provider "aws" {
  region = "us-east-1"
}

resource "aws_organizations_organization" "default" {
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

resource "aws_organizations_organizational_unit" "sales" {
  name      = "Sales"
  parent_id = aws_organizations_organization.default.roots.0.id
}

data "aws_iam_policy_document" "s3_readonly" {
  statement {
    effect      = "Deny"
    not_actions = ["s3:Get*", "s3:List*"]
    resources   = ["arn:aws:s3:::*"]
  }
}

resource "aws_organizations_policy" "s3_readonly" {
  name    = "S3ReadOnly"
  content = data.aws_iam_policy_document.s3_readonly.json
}

resource "aws_organizations_policy_attachment" "sales_s3readonly" {
  target_id = aws_organizations_organizational_unit.sales.id
  policy_id = aws_organizations_policy.s3_readonly.id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.default.roots.0.id
}

resource "aws_organizations_organizational_unit" "dev" {
  name      = "Dev"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_account" "dev" {
  email     = var.dev_account_email
  name      = "dev"
  parent_id = aws_organizations_organizational_unit.dev.id
}

resource "aws_organizations_account" "prod" {
  email     = var.prod_account_email
  name      = "prod"
  parent_id = aws_organizations_organizational_unit.prod.id
}
