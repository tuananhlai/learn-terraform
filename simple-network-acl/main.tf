provider "aws" {
  region = "us-east-1"
}

locals {
  cidr = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                    = "sna-vpc"
  cidr                    = local.cidr
  azs                     = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets          = cidrsubnets(local.cidr, 4, 4)
  map_public_ip_on_launch = true
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "instance_sg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 8
      to_port     = 0
      protocol    = "icmp"
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

data "aws_ami" "amz_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.3.20240219.0-kernel-6.1-x86_64"]
  }
}

resource "aws_instance" "default" {
  for_each = {
    0 = {
      subnet_id = module.vpc.public_subnets[0]
      name      = "InstanceSubnet0"
    },
    1 = {
      subnet_id = module.vpc.public_subnets[1]
      name      = "InstanceSubnet1"
    }
  }

  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [module.instance_sg.security_group_id]
  tags = {
    Name = each.value.name
  }
}

// NOTE: the default network ACL for subnets
// allow all inbound and outbound traffic. However,
// if a custom network ACL is created, it will
// deny all inbound and outbound traffic by default.
resource "aws_network_acl" "first" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.public_subnets[0]]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol = "tcp"
    // NOTE: lower-number rule takes precedence.
    rule_no    = 50
    action     = "deny"
    cidr_block = "1.1.1.1/32"
    from_port  = 443
    to_port    = 443
  }
}

resource "aws_network_acl" "second" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.public_subnets[1]]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "icmp"
    rule_no    = 50
    action     = "deny"
    cidr_block = "1.1.1.1/32"
    from_port  = 8
    to_port    = 0
  }
}

output "commands" {
  value = {
    run_on_instance_subnet_0_success = "ping 1.1.1.1"
    run_on_instance_subnet_1_failed  = "ping 1.1.1.1"
    run_on_instance_subnet_0_failed  = "curl https://1.1.1.1"
    run_on_instance_subnet_1_success = "curl https://1.1.1.1"
  }
}
