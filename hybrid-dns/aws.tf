locals {
  aws_vpc_cidr = "10.16.0.0/16"
}

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "awsVPC"
  cidr = local.aws_vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = cidrsubnets(local.aws_vpc_cidr, 4, 4)

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "aws_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.aws_vpc.vpc_id
  name            = "awsSG"
  use_name_prefix = true

  // NOTE: I created an ALLOW ALL ingress rule by mistake,
  // but even after I remove it in the list below, it's not
  // deleted on AWS.
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
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 53
      to_port     = 53
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

resource "aws_instance" "apps" {
  for_each = {
    0 = { name = "AWS-App-A", subnet_id = module.aws_vpc.private_subnets[0] }
    1 = { name = "AWS-App-B", subnet_id = module.aws_vpc.private_subnets[1] }
  }

  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [module.aws_sg.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.id

  tags = {
    "Name" = each.value.name
  }
}

// Create a private hosted zone with private domain name.
resource "aws_route53_zone" "default" {
  name = "aws.animals4life.org"
  vpc {
    vpc_id = module.aws_vpc.vpc_id
  }
}

resource "aws_route53_record" "default" {
  zone_id = aws_route53_zone.default.zone_id
  name    = "web.aws.animals4life.org"
  type    = "A"
  ttl     = 60
  records = [aws_instance.apps[0].private_ip, aws_instance.apps[1].private_ip]
}

resource "aws_ec2_instance_connect_endpoint" "aws" {
  subnet_id          = module.aws_vpc.private_subnets[1]
  security_group_ids = [module.aws_sg.security_group_id]
}
