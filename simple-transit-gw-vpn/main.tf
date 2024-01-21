provider "aws" {
  region = "us-east-1"
}

locals {
  aws_vpc_cidr   = "10.0.0.0/16"
  local_vpc_cidr = "10.1.0.0/16"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  azs             = ["us-east-1a"]
  cidr            = local.aws_vpc_cidr
  private_subnets = [cidrsubnet(local.aws_vpc_cidr, 4, 0)]
}

resource "aws_security_group" "instance_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_ec2_instance_connect_endpoint" "remote" {
  subnet_id = module.vpc.private_subnets[0]
}

resource "aws_instance" "remote" {
  ami           = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = module.vpc.private_subnets[0]
  tags = {
    Name = "RemoteInstance"
  }
  security_groups             = [aws_security_group.instance_sg.id]
  user_data                   = <<EOF
#!/bin/bash
dnf -y install wget cowsay nginx

echo "#!/bin/sh" > /etc/update-motd.d/40-cow
echo 'cowsay "Hello World!"' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd

echo "<h1>Welcome!</h1>" > /usr/share/nginx/html/index.html

service nginx start
chkconfig nginx on
EOF
  user_data_replace_on_change = true
}


// ==============SIMULATED ON-PREMISE NETWORK=====================

module "local_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  azs                     = ["us-east-1b"]
  cidr                    = local.local_vpc_cidr
  public_subnets          = [cidrsubnet(local.local_vpc_cidr, 4, 0)]
  map_public_ip_on_launch = true
}

resource "aws_security_group" "local_allow_ssh" {
  vpc_id = module.local_vpc.vpc_id

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

# Simulate the customer gateway side using a public EC2 instance.
resource "aws_instance" "local" {
  ami           = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = module.local_vpc.public_subnets[0]
  tags = {
    Name = "LocalInstance"
  }
  security_groups = [aws_security_group.local_allow_ssh.id]
}

resource "aws_eip" "local" {
  domain = "vpc"
}

// ===================SETUP VPN=====================

resource "aws_ec2_transit_gateway" "default" {

}

resource "aws_ec2_transit_gateway_vpc_attachment" "default" {
  transit_gateway_id = aws_ec2_transit_gateway.default.id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = [module.vpc.private_subnets[0]]
}

resource "aws_route" "vpc_transit_gw" {
  route_table_id         = module.vpc.private_route_table_ids[0]
  destination_cidr_block = local.local_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.default.id
}

resource "aws_customer_gateway" "default" {
  bgp_asn    = 65000
  ip_address = aws_eip.local.public_ip
  type       = "ipsec.1"
}

resource "aws_vpn_connection" "default" {
  customer_gateway_id = aws_customer_gateway.default.id
  transit_gateway_id  = aws_ec2_transit_gateway.default.id
  type                = aws_customer_gateway.default.type
}
