provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc_peering_connection" "onprem_aws" {
  vpc_id      = module.onprem_vpc.vpc_id
  peer_vpc_id = module.aws_vpc.vpc_id
  auto_accept = true
}

resource "aws_route" "onprem_aws" {
  for_each = {
    for idx, route_table_id in module.onprem_vpc.private_route_table_ids : idx => { route_table_id = route_table_id }
  }

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = module.aws_vpc.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.onprem_aws.id
}

resource "aws_route" "aws_onprem" {
  for_each = {
    for idx, route_table_id in module.aws_vpc.private_route_table_ids : idx => { route_table_id = route_table_id }
  }

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = module.onprem_vpc.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.onprem_aws.id
}

resource "aws_route53_resolver_endpoint" "inbound" {
  direction          = "INBOUND"
  security_group_ids = [module.aws_sg.security_group_id]

  ip_address {
    subnet_id = module.aws_vpc.private_subnets[0]
  }
  ip_address {
    subnet_id = module.aws_vpc.private_subnets[1]
  }
}

// aws_route53_resolver_endpoint resource doesn't expose
// the ip addresses as output, so we have to read it manually.
data "aws_route53_resolver_endpoint" "inbound" {
  depends_on           = [aws_route53_resolver_endpoint.inbound]
  resolver_endpoint_id = aws_route53_resolver_endpoint.inbound.id
}

locals {
  aws_zone_config = <<EOF
    zone "aws.animals4life.org" { 
      type forward; 
      forward only;
      forwarders { ${join("; ", data.aws_route53_resolver_endpoint.inbound.ip_addresses)}; }; 
    };
  EOF
}

resource "aws_route53_resolver_endpoint" "outbound" {
  direction          = "OUTBOUND"
  security_group_ids = [module.aws_sg.security_group_id]

  ip_address {
    subnet_id = module.aws_vpc.private_subnets[0]
  }
  ip_address {
    subnet_id = module.aws_vpc.private_subnets[1]
  }
}

resource "aws_route53_resolver_rule" "outbound" {
  rule_type   = "FORWARD"
  domain_name = "corp.animals4life.org"

  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id
  target_ip {
    ip = aws_instance.onprem_dns_a.private_ip
  }
  target_ip {
    ip = aws_instance.onprem_dns_b.private_ip
  }
}

resource "aws_route53_resolver_rule_association" "outbound" {
  resolver_rule_id = aws_route53_resolver_rule.outbound.id
  vpc_id           = module.aws_vpc.vpc_id
}
