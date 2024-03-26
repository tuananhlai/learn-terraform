provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cidr            = "10.0.0.0/16"
  subnets         = cidrsubnets(local.cidr, 4, 4, 4, 4)
  private_subnets = slice(local.subnets, 0, 2)
  public_subnets  = slice(local.subnets, 2, 4)
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                    = "shared-vpc"
  cidr                    = local.cidr
  azs                     = local.azs
  public_subnets          = local.public_subnets
  private_subnets         = local.private_subnets
  map_public_ip_on_launch = true
}

resource "aws_ram_sharing_with_organization" "default" {

}

resource "aws_ram_resource_share" "vpc" {
  name                      = "shared-vpc"
  allow_external_principals = false
}

resource "aws_ram_principal_association" "default" {
  resource_share_arn = aws_ram_resource_share.vpc.arn
  principal          = var.resource_share_principal_arn
}

resource "aws_ram_resource_association" "public_subnet" {
  resource_share_arn = aws_ram_resource_share.vpc.arn
  resource_arn       = module.vpc.public_subnet_arns[0]
}

resource "aws_ram_resource_association" "private_subnet" {
  resource_share_arn = aws_ram_resource_share.vpc.arn
  resource_arn       = module.vpc.private_subnet_arns[0]
}

# See this link below if you get an Organization Not Found error.
# https://stackoverflow.com/questions/75393891/organization-could-not-be-found

output "shared_vpc" {
  value = {
    vpc_id            = module.vpc.vpc_id
    private_subnet_id = module.vpc.private_subnets[0]
    public_subnet_id  = module.vpc.public_subnets[0]
  }
}

# After applying this Terraform template, visit https://us-east-1.console.aws.amazon.com/ram/home?region=us-east-1#SharedResourceShares:
# using the AWS account you shared the VPC with. A resource shared called `shared-vpc` should be present.
