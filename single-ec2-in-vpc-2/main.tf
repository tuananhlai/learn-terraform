provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "MultiTieredVPCWithModule"
  cidr = "10.16.0.0/16"

  azs                     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets          = ["10.16.48.0/20", "10.16.112.0/20", "10.16.176.0/20"]
  public_subnet_names     = ["sn-web-A", "sn-web-B", "sn-web-C"]
  private_subnets         = ["10.16.32.0/20", "10.16.96.0/20", "10.16.160.0/20", "10.16.0.0/20", "10.16.64.0/20", "10.16.128.0/20"]
  private_subnet_names    = ["sn-app-A", "sn-app-B", "sn-app-C", "sn-reserved-A", "sn-reserved-B", "sn-reserved-C"]
  database_subnets        = ["10.16.16.0/20", "10.16.80.0/20", "10.16.144.0/20"]
  database_subnet_names   = ["sn-db-A", "sn-db-B", "sn-db-C"]
  map_public_ip_on_launch = true
  igw_tags = {
    Name = "igw-MultiTieredVPCWithModule"
  }
}

resource "aws_instance" "single_instance" {
  ami           = "ami-0230bd60aa48260c6"
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]

  tags = {
    Name = "single-instance-in-vpc-2"
  }
}
