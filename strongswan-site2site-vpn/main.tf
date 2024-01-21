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

module "remote_instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "RemoteInstanceSg"
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

# resource "aws_ec2_instance_connect_endpoint" "remote" {
#   subnet_id = module.vpc.private_subnets[0]
# }

resource "aws_instance" "remote" {
  ami           = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = module.vpc.private_subnets[0]
  tags = {
    Name = "RemoteInstance"
  }
  vpc_security_group_ids      = [module.remote_instance_sg.security_group_id]
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

module "local_instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.local_vpc.vpc_id
  name            = "LocalInstanceSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
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

# Simulate the customer gateway side using a public EC2 instance.
resource "aws_instance" "local" {
  ami           = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = module.local_vpc.public_subnets[0]
  tags = {
    Name = "LocalInstance"
  }
  vpc_security_group_ids = [module.local_instance_sg.security_group_id]
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

locals {
  tunnel1_neighbor_ip_address  = aws_vpn_connection.default.tunnel1_vgw_inside_address
  tunnel2_neighbor_ip_address  = aws_vpn_connection.default.tunnel2_vgw_inside_address
  tunnel1_vgw_inside_addresses = "${aws_vpn_connection.default.tunnel1_vgw_inside_address}/30"
  tunnel1_cgw_inside_addresses = "${aws_vpn_connection.default.tunnel1_cgw_inside_address}/30"
  tunnel2_vgw_inside_addresses = "${aws_vpn_connection.default.tunnel2_vgw_inside_address}/30"
  tunnel2_cgw_inside_addresses = "${aws_vpn_connection.default.tunnel2_cgw_inside_address}/30"
}

resource "aws_secretsmanager_secret" "preshared_keys" {
  for_each = {
    "onPrem" = {
      name_prefix = "site2site/onPremPsk"
    }
    "aws" = {
      name_prefix = "site2site/awsPsk"
    }
  }
  name_prefix = each.value.name_prefix
}

resource "aws_secretsmanager_secret_version" "preshared_keys" {
  for_each = {
    "onPrem" = {
      secret_id = aws_secretsmanager_secret.preshared_keys["onPrem"].id
      psk       = aws_vpn_connection.default.tunnel1_preshared_key
    }
    "aws" = {
      secret_id = aws_secretsmanager_secret.preshared_keys["aws"].id
      psk       = aws_vpn_connection.default.tunnel2_preshared_key
    }
  }
  secret_id     = each.value.secret_id
  secret_string = <<EOF
  {
    "psk": "${each.value.psk}"
  }
  EOF
}

resource "aws_cloudformation_stack" "strong_swan_vpn_gateway" {
  name         = "VpnGateway"
  capabilities = ["CAPABILITY_NAMED_IAM"]
  parameters = {
    pTunnel1PskSecretName        = aws_secretsmanager_secret.preshared_keys["onPrem"].name
    pTunnel1VgwOutsideIpAddress  = aws_vpn_connection.default.tunnel1_address
    pTunnel1CgwInsideIpAddress   = local.tunnel1_cgw_inside_addresses
    pTunnel1VgwInsideIpAddress   = local.tunnel1_vgw_inside_addresses
    pTunnel1VgwBgpAsn            = aws_vpn_connection.default.tunnel1_bgp_asn
    pTunnel1BgpNeighborIpAddress = local.tunnel1_neighbor_ip_address
    pTunnel2PskSecretName        = aws_secretsmanager_secret.preshared_keys["aws"].name
    pTunnel2VgwOutsideIpAddress  = aws_vpn_connection.default.tunnel2_address
    pTunnel2CgwInsideIpAddress   = local.tunnel2_cgw_inside_addresses
    pTunnel2VgwInsideIpAddress   = local.tunnel2_vgw_inside_addresses
    pTunnel2VgwBgpAsn            = aws_vpn_connection.default.tunnel2_bgp_asn
    pTunnel2BgpNeighborIpAddress = local.tunnel2_neighbor_ip_address
    pUseElasticIp                = "true"
    pEipAllocationId             = aws_eip.local.allocation_id
    pLocalBgpAsn                 = aws_customer_gateway.default.bgp_asn
    pVpcId                       = module.local_vpc.vpc_id
    pVpcCidr                     = module.local_vpc.vpc_cidr_block
    pSubnetId                    = module.local_vpc.public_subnets[0]
  }
  template_body = file("${path.module}/stack.yaml")
}

output "stack_parameters" {
  value = {
    pTunnel1PskSecretName        = aws_secretsmanager_secret.preshared_keys["onPrem"].name
    pTunnel1VgwOutsideIpAddress  = aws_vpn_connection.default.tunnel1_address
    pTunnel1CgwInsideIpAddress   = local.tunnel1_cgw_inside_addresses
    pTunnel1VgwInsideIpAddress   = local.tunnel1_vgw_inside_addresses
    pTunnel1VgwBgpAsn            = aws_vpn_connection.default.tunnel1_bgp_asn
    pTunnel1BgpNeighborIpAddress = local.tunnel1_neighbor_ip_address
    pTunnel2PskSecretName        = aws_secretsmanager_secret.preshared_keys["aws"].name
    pTunnel2VgwOutsideIpAddress  = aws_vpn_connection.default.tunnel2_address
    pTunnel2CgwInsideIpAddress   = local.tunnel2_cgw_inside_addresses
    pTunnel2VgwInsideIpAddress   = local.tunnel2_vgw_inside_addresses
    pTunnel2VgwBgpAsn            = aws_vpn_connection.default.tunnel2_bgp_asn
    pTunnel2BgpNeighborIpAddress = local.tunnel2_neighbor_ip_address
    pUseElasticIp                = "true"
    pEipAllocationId             = aws_eip.local.allocation_id
    pLocalBgpAsn                 = aws_customer_gateway.default.bgp_asn
    pVpcId                       = module.local_vpc.vpc_id
    pVpcCidr                     = module.local_vpc.vpc_cidr_block
    pSubnetId                    = module.local_vpc.public_subnets[0]
  }
}

locals {
  vpnGatewayPrivateIp = aws_cloudformation_stack.strong_swan_vpn_gateway.outputs["vpnGatewayPrivateIp"]
  vpnGatewayId        = aws_cloudformation_stack.strong_swan_vpn_gateway.outputs["vpnGatewayInstanceId"]
}

output "private_ip_addresses" {
  value = {
    vpnGatewayPrivateIp     = local.vpnGatewayPrivateIp
    vpnGatewayInstanceId    = local.vpnGatewayId
    remoteInstancePrivateIp = aws_instance.remote.private_ip
  }
}

resource "aws_network_interface" "vpn_gateway" {
  subnet_id = module.local_vpc.public_subnets[0]
  attachment {
    instance = local.vpnGatewayId
    device_index = 1
  }
}

resource "aws_route" "local" {
  route_table_id         = module.local_vpc.public_route_table_ids[0]
  destination_cidr_block = module.vpc.vpc_cidr_block
  network_interface_id   = aws_network_interface.vpn_gateway.id
}
