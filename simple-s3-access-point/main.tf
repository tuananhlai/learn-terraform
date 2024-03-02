provider "aws" {
  region = "us-east-1"
}

// ======Setup======
// Note: Somehow, if I tries to create an public accessible access point,
// I will get an AccessDenied when trying to update the access endpoint
// policy. So, I have to create a private access point that only accessible
// within a VPC.

locals {
  vpc_cidr = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "ap-example-vpc"
  cidr = local.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 1)
  private_subnets = cidrsubnets(local.vpc_cidr, 4)
}

resource "aws_iam_role" "default" {
  name_prefix = "ap-instance-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "default" {
  name_prefix = "ap-instance-profile-"
  role        = aws_iam_role.default.id
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name            = "ap-example-instance-sg"
  vpc_id          = module.vpc.vpc_id
  use_name_prefix = true

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

resource "aws_instance" "default" {
  ami                    = "ami-0230bd60aa48260c6"
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.default.name
  vpc_security_group_ids = [module.instance_sg.security_group_id]
  subnet_id              = module.vpc.private_subnets[0]

  tags = {
    Name = "ap-example-instance"
  }
}

resource "aws_ec2_instance_connect_endpoint" "default" {
  subnet_id          = module.vpc.private_subnets[0]
  security_group_ids = [module.instance_sg.security_group_id]
}

// Allow the instance to connect to the S3 bucket.
resource "aws_vpc_endpoint" "s3" {
  vpc_endpoint_type = "Gateway"
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = module.vpc.private_route_table_ids
}

resource "aws_s3_bucket" "default" {
  bucket_prefix = "ap-example-"
}

resource "aws_s3_object" "default" {
  bucket  = aws_s3_bucket.default.bucket
  key     = "hello.txt"
  content = "Hello, World!"
}

// =====Provision the S3 Access Point=====
resource "aws_s3_access_point" "default" {
  name   = "ap-example-access-point"
  bucket = aws_s3_bucket.default.bucket

  vpc_configuration {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_s3control_access_point_policy" "default" {
  access_point_arn = aws_s3_access_point.default.arn
  policy           = <<EOF
{
    "Version":"2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Principal": "*", 
        "Action": "s3:ListBucket",
        "Resource": "${aws_s3_access_point.default.arn}"
      }
    ]
}
  EOF
}

output "commands" {
  value = {
    "list_s3_bucket"                  = "aws s3 ls s3://${aws_s3_bucket.default.bucket}"
    "list_s3_bucket_via_access_point" = "echo 'this comment will fail with AccessDenied error' && aws s3 ls s3://${aws_s3_access_point.default.arn}"
    "get_s3_object"                   = "aws s3 cp s3://${aws_s3_bucket.default.bucket}/hello.txt -"
    "get_s3_object_via_access_point"  = "aws s3 cp s3://${aws_s3_access_point.default.arn}/hello.txt -"
  }
  description = "Commands to run to verify the functionality of the S3 bucket and access point."
}
