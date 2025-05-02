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

  name                 = "simple-rds-vpc"
  cidr                 = local.default_vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  public_subnets       = cidrsubnets(local.default_vpc_cidr, 4, 4, 4)
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "random_password" "db_password" {
  length  = 16
  special = false
  upper   = true
  numeric = true
}

module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  vpc_id          = module.vpc.vpc_id
  name            = "simple-rds-db-sg"
  use_name_prefix = true

  // For demo purpose only. The ingress and egress rules should be much more restrictive in production.
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
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

resource "aws_db_subnet_group" "primary" {
  name       = "simple-rds-db-subnet-group"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_parameter_group" "primary" {
  name_prefix = "simple-rds-db-parameter-group"
  family      = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_instance" "primary" {
  identifier_prefix      = "simple-rds-"
  engine                 = "postgres"
  engine_version         = "17.2"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 5
  db_name                = "postgres"
  username               = "postgres"
  password               = random_password.db_password.result
  skip_final_snapshot    = true
  vpc_security_group_ids = [module.db_sg.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  parameter_group_name   = aws_db_parameter_group.primary.name
  // For demonstration purpose only. It's recommended to apply changes to the database
  // during its maintenance window.
  apply_immediately = true
  // For demonstration purposes only. Don't make a production database publicly accessible.
  publicly_accessible = true
}

output "primary" {
  value = {
    password = nonsensitive(random_password.db_password.result),
    username = aws_db_instance.primary.username
    address  = aws_db_instance.primary.address
  }
}
