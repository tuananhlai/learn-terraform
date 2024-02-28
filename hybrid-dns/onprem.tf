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
