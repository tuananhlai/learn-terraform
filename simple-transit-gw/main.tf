provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  for_each = {
    "VpcA" = {
      name            = "VpcA"
      cidr            = "10.0.0.0/16"
      azs             = ["us-east-1a"]
      private_subnets = ["10.0.16.0/20"]
    }
    "VpcB" = {
      name            = "VpcB"
      cidr            = "10.1.0.0/16"
      azs             = ["us-east-1a"]
      private_subnets = ["10.1.16.0/20"]
    }
    "VpcC" = {
      name            = "VpcC"
      cidr            = "10.2.0.0/16"
      azs             = ["us-east-1a"]
      private_subnets = ["10.2.16.0/20"]
    }
  }

  name            = each.value.name
  cidr            = each.value.cidr
  azs             = each.value.azs
  private_subnets = each.value.private_subnets
}

resource "aws_ec2_transit_gateway" "default" {

}

resource "aws_ec2_transit_gateway_vpc_attachment" "default" {
  for_each = {
    "VpcA" = {
      vpc_id     = module.vpc["VpcA"].vpc_id
      subnet_ids = [module.vpc["VpcA"].private_subnets[0]]
    }
    "VpcB" = {
      vpc_id     = module.vpc["VpcB"].vpc_id
      subnet_ids = [module.vpc["VpcB"].private_subnets[0]]
    }
    "VpcC" = {
      vpc_id     = module.vpc["VpcC"].vpc_id
      subnet_ids = [module.vpc["VpcC"].private_subnets[0]]
    }
  }
  vpc_id             = each.value.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.default.id
  subnet_ids         = each.value.subnet_ids
}

resource "aws_security_group" "instance_sg" {
  for_each = {
    "VpcA" = {
      vpc_id = module.vpc["VpcA"].vpc_id
    }
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
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

resource "aws_instance" "default" {
  for_each = {
    "VpcA" = {
      name            = "InstanceA"
      subnet_id       = module.vpc["VpcA"].private_subnets[0]
      security_groups = [aws_security_group.instance_sg["VpcA"].id]
    }
    "VpcB" = {
      name            = "InstanceB"
      subnet_id       = module.vpc["VpcB"].private_subnets[0]
      security_groups = [aws_security_group.instance_sg["VpcB"].id]
    }
    "VpcC" = {
      name            = "InstanceC"
      subnet_id       = module.vpc["VpcC"].private_subnets[0]
      security_groups = [aws_security_group.instance_sg["VpcC"].id]
    }
  }

  ami           = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = each.value.subnet_id
  tags = {
    Name = each.value.name
  }
  security_groups = each.value.security_groups
}

resource "aws_ec2_instance_connect_endpoint" "default" {
  for_each = {
    "VpcA" = {
      subnet_id          = module.vpc["VpcA"].private_subnets[0]
      security_group_ids = [aws_security_group.instance_sg["VpcA"].id]
    }
  }
  security_group_ids = each.value.security_group_ids
  subnet_id          = each.value.subnet_id
}

resource "aws_route" "vpca_transit_gw" {
  # NOTE: In order to send traffic between two VPCs, routes to transit gateway must be
  # added in BOTH source and destination VPC's route tables.
  for_each = {
    "VpcA" = {
      route_table_id = module.vpc["VpcA"].private_route_table_ids[0]
    }
    "VpcB" = {
      route_table_id = module.vpc["VpcB"].private_route_table_ids[0]
    }
    "VpcC" = {
      route_table_id = module.vpc["VpcC"].private_route_table_ids[0]
    }
  }
  route_table_id = each.value.route_table_id
  # Direct the traffic to the transit gateway for any private IPs. Used for simplification.
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.default.id
}

# Transit gateway routing is TRANSITIVE. In other word, by connecting
# VPC A, B and C to the transit gateway, traffic can flow between any pair of VPC.
