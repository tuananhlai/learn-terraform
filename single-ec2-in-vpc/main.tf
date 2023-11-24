module "multi_tiered_vpc" {
  source = "../multi-tiered-vpc"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "single_instance" {
  ami           = "ami-0230bd60aa48260c6"
  instance_type = "t2.micro"
  subnet_id     = module.multi_tiered_vpc.sn_web_a_id

  tags = {
    Name = "single-instance-in-vpc"
  }
}
