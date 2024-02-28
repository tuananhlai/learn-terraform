provider "aws" {
  region = "us-east-1"
}

// ==================COMMON RESOURCES================== 

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_ami" "amz_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  // NOTE: using name_regex takes much longer
  // than using filter block.
  // name_regex = "*"

  filter {
    name   = "name"
    values = ["al2023-ami-2023.3.20240219.0-kernel-6.1-x86_64"]
  }
}

resource "aws_iam_role" "ec2" {
  name = "EC2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2" {
  name = "EC2RolePolicy"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2.id
}


// ==================AWS NETWORK================== 

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

// Create a private hosted zone in Route 53 with private domain name.
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

// Create an inbound endpoint to allows on-premise
// applications to use Route53 to resolve domain
// names.
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

// ==================SIMULATED ON-PREMISE NETWORK================== 
locals {
  onprem_vpc_cidr = "192.168.10.0/24"
}

module "onprem_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "onPremVPC"
  cidr = local.onprem_vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = cidrsubnets(local.onprem_vpc_cidr, 1, 1)
}

// Allow Amazon Linux EC2 instances in private subnet
// to access YUM repository for package installs & updates.
resource "aws_vpc_endpoint" "s3" {
  vpc_endpoint_type = "Gateway"
  vpc_id            = module.onprem_vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = module.onprem_vpc.private_route_table_ids
}

module "onprem_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.onprem_vpc.vpc_id
  name            = "onPremSG"
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
    // NOTE: This rule is for the DNS server instances. DNS supports 
    // both UDP and TCP, so security groups must allow both protocol 
    // in order for the resolver to work correctly.
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

resource "aws_instance" "onprem_app" {
  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = module.onprem_vpc.private_subnets[1]
  vpc_security_group_ids = [module.onprem_sg.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.id

  tags = {
    "Name" = "OnPremApp"
  }
}

resource "aws_instance" "onprem_dns_b" {
  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = module.onprem_vpc.private_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.ec2.id
  vpc_security_group_ids = [module.onprem_sg.security_group_id]
  tags = {
    Name = "OnPremDNS-B"
  }

  user_data                   = <<-EOF
    #!/bin/bash -xe
    yum update -y
    yum install bind bind-utils -y
    cat <<EOL > /etc/named.conf
    options {
      directory "/var/named";
      dump-file "/var/named/data/cache_dump.db";
      statistics-file "/var/named/data/named_stats.txt";
      memstatistics-file "/var/named/data/named_mem_stats.txt";
      allow-query { any; };
      recursion yes;
      forward first;
      forwarders {
        192.168.10.2;
      };
      dnssec-enable yes;
      dnssec-validation yes;
      dnssec-lookaside auto;
      /* Path to ISC DLV key */
      bindkeys-file "/etc/named.iscdlv.key";
      managed-keys-directory "/var/named/dynamic";
    };
    zone "corp.animals4life.org" IN {
        type master;
        file "corp.animals4life.org.zone";
        allow-update { none; };
    };
    ${local.aws_zone_config}
    EOL
    cat <<EOL > /var/named/corp.animals4life.org.zone
    \$TTL 86400
    @   IN  SOA     ns1.mydomain.com. root.mydomain.com. (
            2013042201  ;Serial
            3600        ;Refresh
            1800        ;Retry
            604800      ;Expire
            86400       ;Minimum TTL
    )
    ; Specify our two nameservers
        IN	NS		dnsA.corp.animals4life.org.
        IN	NS		dnsB.corp.animals4life.org.
    ; Resolve nameserver hostnames to IP, replace with your two droplet IP addresses.
    dnsA		IN	A		1.1.1.1
    dnsB	  IN	A		8.8.8.8

    ; Define hostname -> IP pairs which you wish to resolve
    @		  IN	A		${aws_instance.onprem_app.private_ip}
    app		IN	A	  ${aws_instance.onprem_app.private_ip}
    EOL
    service named restart
    chkconfig named on
    EOF
  user_data_replace_on_change = true
}

resource "aws_ec2_instance_connect_endpoint" "onprem" {
  subnet_id          = module.onprem_vpc.private_subnets[1]
  security_group_ids = [module.onprem_sg.security_group_id]
}

resource "aws_instance" "onprem_dns_a" {
  ami                    = data.aws_ami.amz_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = module.onprem_vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2.id
  vpc_security_group_ids = [module.onprem_sg.security_group_id]
  tags = {
    Name = "OnPremDNS-A"
  }

  user_data                   = <<-EOF
    #!/bin/bash -xe
    yum update -y
    yum install bind bind-utils -y
    cat <<EOS > /etc/named.conf
    options {
      directory	"/var/named";
      dump-file	"/var/named/data/cache_dump.db";
      statistics-file "/var/named/data/named_stats.txt";
      memstatistics-file "/var/named/data/named_mem_stats.txt";
      allow-query { any; };
      allow-transfer     { localhost; ${aws_instance.onprem_dns_b.private_ip}; };
      recursion yes;
      forward first;
      forwarders {
        192.168.10.2;
      };
      dnssec-enable yes;
      dnssec-validation yes;
      dnssec-lookaside auto;
      /* Path to ISC DLV key */
      bindkeys-file "/etc/named.iscdlv.key";
      managed-keys-directory "/var/named/dynamic";
    };
    zone "corp.animals4life.org" IN {
        type master;
        file "corp.animals4life.org.zone";
        allow-update { none; };
    };
    ${local.aws_zone_config}
    EOS
    cat <<EOS > /var/named/corp.animals4life.org.zone
    \$TTL 86400
    @   IN  SOA     ns1.mydomain.com. root.mydomain.com. (
            2013042201  ;Serial
            3600        ;Refresh
            1800        ;Retry
            604800      ;Expire
            86400       ;Minimum TTL
    )
    ; Specify our two nameservers
        IN	NS		dnsA.corp.animals4life.org.
        IN	NS		dnsB.corp.animals4life.org.
    ; Resolve nameserver hostnames to IP, replace with your two droplet IP addresses.
    dnsA		IN	A		1.1.1.1
    dnsB	  IN	A		8.8.8.8

    ; Define hostname -> IP pairs which you wish to resolve
    @		  IN	A		${aws_instance.onprem_app.private_ip}
    app		IN	A	  ${aws_instance.onprem_app.private_ip}
    EOS
    service named restart
    chkconfig named on
  EOF
  user_data_replace_on_change = true
}

// Create an outbound so that applications on AWS can
// resolve domain names for on-premise applications.
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

// A resolver rule must be associated with a VPC before it's usable.
resource "aws_route53_resolver_rule_association" "outbound" {
  resolver_rule_id = aws_route53_resolver_rule.outbound.id
  vpc_id           = module.aws_vpc.vpc_id
}

// Create a VPC peering connection to simulate a Direct Connect between on-premise and AWS network.
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
