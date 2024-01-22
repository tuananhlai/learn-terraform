provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "SimpleWafVpc"
  azs  = ["us-east-1a", "us-east-1b"]
  cidr = "10.0.0.0/16"
  # A load balancer must be attached to 2 or more subnets in different AZs.
  public_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "InstanceSg"
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
    {
      from_port   = 80
      to_port     = 80
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

module "lb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "AlbSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
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

resource "aws_instance" "default" {
  ami                         = "ami-0b5bf7c3d5a739610" #Bitnami Debian with Wordpress
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.instance_sg.security_group_id]
  associate_public_ip_address = true
}

locals {
  target_group_port     = 80
  target_group_protocol = "HTTP"
}

resource "aws_alb_target_group" "default" {
  vpc_id   = module.vpc.vpc_id
  port     = local.target_group_port
  protocol = local.target_group_protocol
}

resource "aws_alb_target_group_attachment" "default" {
  target_group_arn = aws_alb_target_group.default.arn
  target_id        = aws_instance.default.id
}

resource "aws_alb" "default" {
  subnets         = module.vpc.public_subnets
  security_groups = [module.lb_sg.security_group_id]
  internal        = false
}

resource "aws_alb_listener" "default" {
  load_balancer_arn = aws_alb.default.arn
  port              = local.target_group_port
  protocol          = local.target_group_protocol
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default.arn
  }
}

resource "aws_s3_bucket" "waf_logs" {
  bucket_prefix = "aws-waf-logs-demo"
}
