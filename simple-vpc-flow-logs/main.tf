provider "aws" {
  region = "us-east-1"
}

locals {
  vpc_cidr = "10.16.0.0/16"
}

data "aws_availability_zones" "default" {
  state = "available"
}

data "aws_ami" "amz_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-2.0.20240223.0-x86_64-gp2"]
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_flow_logs" {
  role       = aws_iam_role.vpc_flow_logs.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "svfl-vpc"
  cidr = local.vpc_cidr

  azs                     = slice(data.aws_availability_zones.default.names, 0, 1)
  public_subnets          = cidrsubnets(local.vpc_cidr, 4)
  map_public_ip_on_launch = true

  enable_flow_log                      = true
  flow_log_cloudwatch_iam_role_arn     = aws_iam_role.vpc_flow_logs.arn
  create_flow_log_cloudwatch_log_group = true
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name            = "instance-sg-"
  vpc_id          = module.vpc.vpc_id
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    // Comment out the line below to create a REJECT log when pinging.
    {
      from_port   = -1
      to_port     = -1
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

resource "aws_instance" "default" {
  for_each = {
    "source" = {
      name = "svfl-source-instance"
    }
    "destination" = {
      name = "svfl-destination-instance"
    }
  }

  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.instance_sg.security_group_id]

  tags = {
    Name = each.value.name
  }
}


output "source_instance_commands" {
  value = {
    ping_public_service       = "ping 8.8.8.8"
    ping_destination_instance = "ping ${aws_instance.default["destination"].private_ip}"
  }
}

output "infos" {
  value = {
    source_instance_eni_id      = aws_instance.default["source"].primary_network_interface_id
    destination_instance_eni_id = aws_instance.default["destination"].primary_network_interface_id
  }
}
