provider "aws" {
  region = "us-east-1"
}

locals {
  vpc_cidr     = "10.16.0.0/16"
  subnet_cidrs = cidrsubnets(local.vpc_cidr, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4)
}

data "aws_availability_zones" "default" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.3.20240219.0-kernel-6.1-x86_64"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "MultiTieredVPCWithModule"
  cidr = local.vpc_cidr

  azs                     = slice(data.aws_availability_zones.default.names, 0, 3)
  public_subnets          = slice(local.subnet_cidrs, 0, 3)
  public_subnet_names     = ["sn-web-A", "sn-web-B", "sn-web-C"]
  private_subnets         = slice(local.subnet_cidrs, 3, 9)
  private_subnet_names    = ["sn-app-A", "sn-app-B", "sn-app-C", "sn-reserved-A", "sn-reserved-B", "sn-reserved-C"]
  database_subnets        = slice(local.subnet_cidrs, 9, 12)
  database_subnet_names   = ["sn-db-A", "sn-db-B", "sn-db-C"]
  map_public_ip_on_launch = true
  igw_tags = {
    Name = "igw-MultiTieredVPCWithModule"
  }
}

resource "aws_instance" "single_instance" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]

  tags = {
    Name = "single-instance-in-vpc-2"
  }
}
