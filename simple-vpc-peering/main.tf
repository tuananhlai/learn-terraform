provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  for_each = {
    "VpcA" = {
      name = "VpcA"
      cidr = "10.0.0.0/16"
      azs = ["us-east-1a"]
      private_subnets = ["10.0.16.0/20"]
    }
    "VpcB" = {
      name = "VpcB"
      cidr = "10.1.0.0/16"
      azs = ["us-east-1a"]
      private_subnets = ["10.1.16.0/20"]
    }
    "VpcC" = {
      name = "VpcC"
      cidr = "10.2.0.0/16"
      azs = ["us-east-1a"]
      private_subnets = ["10.2.16.0/20"]
    }
  }

  name                    = each.value.name
  cidr                    = each.value.cidr
  azs                     = each.value.azs
  private_subnets         = each.value.private_subnets
}

resource "aws_security_group" "allow_ssh" {
  vpc_id = module.vpc["VpcA"].vpc_id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::0/0"]
  }
}


resource "aws_security_group" "allow_icmp" {
  for_each = {
    "VpcB" = {
      vpc_id = module.vpc["VpcB"].vpc_id
    }
    "VpcC" = {
      vpc_id = module.vpc["VpcC"].vpc_id
    }
  }

  vpc_id = each.value.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
  }
}

resource "aws_instance" "default" {
  for_each = {
    "VpcA" = {
      name = "InstanceA"
      subnet_id = module.vpc["VpcA"].private_subnets[0]
      security_groups = [aws_security_group.allow_ssh.id]
    }
    "VpcB" = {
      name = "InstanceB"
      subnet_id = module.vpc["VpcB"].private_subnets[0]
      security_groups = [aws_security_group.allow_icmp["VpcB"].id]
    }
    "VpcC" = {
      name = "InstanceC"
      subnet_id = module.vpc["VpcC"].private_subnets[0]
      security_groups = [aws_security_group.allow_icmp["VpcC"].id]
    }
  }

  ami                         = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type               = "t2.micro"
  subnet_id = each.value.subnet_id
  tags = {
    Name = each.value.name
  }
  security_groups = each.value.security_groups
}

resource "aws_ec2_instance_connect_endpoint" "default" {
  security_group_ids = [aws_security_group.allow_ssh.id]
  subnet_id = module.vpc["VpcA"].private_subnets[0]
}

resource "aws_vpc_peering_connection" "vpca_vpcc" {
  vpc_id = module.vpc["VpcA"].vpc_id
  peer_vpc_id = module.vpc["VpcC"].vpc_id
  auto_accept = true
}

resource "aws_route" "vpca_vpcc" {
  route_table_id = module.vpc["VpcA"].private_route_table_ids[0]
  destination_cidr_block = module.vpc["VpcC"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpca_vpcc.id
}

resource "aws_route" "vpcc_vpca" {
  route_table_id = module.vpc["VpcC"].private_route_table_ids[0]
  destination_cidr_block = module.vpc["VpcA"].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpca_vpcc.id
}

output "instance_a_ip_address" {
  value = aws_instance.default["VpcA"].private_ip
}

output "instance_b_ip_address" {
  value = aws_instance.default["VpcB"].private_ip
}

output "instance_c_ip_address" {
  value = aws_instance.default["VpcC"].private_ip
}
