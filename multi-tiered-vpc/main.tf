provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "multi_tiered_vpc" {
  cidr_block = "10.16.0.0/16"
  tags = {
    Name = "MultiTieredVPC"
  }
}

resource "aws_internet_gateway" "igw_multi_tiered_vpc" {
  vpc_id = aws_vpc.multi_tiered_vpc.id
}

resource "aws_route_table" "rt_sn_web" {
  tags = {
    Name = "PublicRouteTable"
  }
  vpc_id = aws_vpc.multi_tiered_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_multi_tiered_vpc.id
  }
}

resource "aws_subnet" "sn_web" {
  for_each = {
    "webA" = { name = "sn-web-A", cidr_block = "10.16.48.0/20", zone = "us-east-1a" }
    "webB" = { name = "sn-web-B", cidr_block = "10.16.112.0/20", zone = "us-east-1b" }
    "webC" = { name = "sn-web-C", cidr_block = "10.16.176.0/20", zone = "us-east-1c" }
  }
  tags = {
    Name = each.value.name
  }
  vpc_id                  = aws_vpc.multi_tiered_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.zone
  map_public_ip_on_launch = true
}

resource "aws_route_table_association" "rt_sn_web_association" {
  for_each       = aws_subnet.sn_web
  route_table_id = aws_route_table.rt_sn_web.id
  subnet_id      = each.value.id
}

resource "aws_subnet" "sn_db" {
  for_each = {
    "dbA" = { name = "sn-db-A", cidr_block = "10.16.16.0/20", zone = "us-east-1a" }
    "dbB" = { name = "sn-db-B", cidr_block = "10.16.80.0/20", zone = "us-east-1b" }
    "dbC" = { name = "sn-db-C", cidr_block = "10.16.144.0/20", zone = "us-east-1c" }
  }
  tags = {
    Name = each.value.name
  }
  vpc_id                  = aws_vpc.multi_tiered_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false
}

resource "aws_subnet" "sn_app" {
  for_each = {
    "appA" = { name = "sn-app-A", cidr_block = "10.16.32.0/20", zone = "us-east-1a" }
    "appB" = { name = "sn-app-B", cidr_block = "10.16.96.0/20", zone = "us-east-1b" }
    "appC" = { name = "sn-app-C", cidr_block = "10.16.160.0/20", zone = "us-east-1c" }
  }
  tags = {
    Name = each.value.name
  }
  vpc_id                  = aws_vpc.multi_tiered_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false
}

resource "aws_subnet" "sn_reserved" {
  for_each = {
    "reservedA" = { name = "sn-reserved-A", cidr_block = "10.16.0.0/20", zone = "us-east-1a" }
    "reservedB" = { name = "sn-reserved-B", cidr_block = "10.16.64.0/20", zone = "us-east-1b" }
    "reservedC" = { name = "sn-reserved-C", cidr_block = "10.16.128.0/20", zone = "us-east-1c" }
  }
  tags = {
    Name = each.value.name
  }
  vpc_id                  = aws_vpc.multi_tiered_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false
}

output "vpc_id" {
  value = aws_vpc.multi_tiered_vpc.id
}

output "sn_web_a_id" {
  value = aws_subnet.sn_web["webA"].id
}
