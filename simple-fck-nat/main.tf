provider "aws" {
  region = "us-east-1"
}

locals {
  default_vpc_cidr = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                    = "simple-fck-nat-vpc"
  cidr                    = local.default_vpc_cidr
  azs                     = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets          = ["10.0.0.0/20", "10.0.16.0/20"]
  private_subnets         = ["10.0.32.0/20", "10.0.48.0/20"]
  map_public_ip_on_launch = true
}


# Uncomment this resource after you run `terraform apply` for the first time.
#
# module "fck-nat" {
#   source  = "RaJiska/fck-nat/aws"
#   version = "~> 1.0"

#   instance_type = "t2.micro"
#   name          = "simple-fck-nat"
#   vpc_id        = module.vpc.vpc_id
#   subnet_id     = module.vpc.public_subnets[0]

#   update_route_tables = true
#   route_tables_ids = {
#     for index, rt_id in toset(module.vpc.private_route_table_ids) :
#     rt_id => rt_id
#   }
# }

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name            = "simple-fck-nat-sg-"
  vpc_id          = module.vpc.vpc_id
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::0/0"
    }
  ]
}

resource "aws_ec2_instance_connect_endpoint" "default" {
  subnet_id          = module.vpc.private_subnets[0]
  security_group_ids = [module.instance_sg.security_group_id]
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-20*-kernel-6.1-x86_64"]
  }
}

resource "aws_instance" "single_instance" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [module.instance_sg.security_group_id]
  subnet_id              = module.vpc.private_subnets[0]

  tags = {
    Name = "single-fck-nat-instance"
  }
}

# Try connect to the EC2 instance above using Instance Connect endpoint
# and check if they have internet connection with the command below.
#
# curl http://example.com
