provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name            = "PrivateS3Vpc"
  azs             = ["us-east-1a"]
  cidr            = "10.0.0.0/16"
  private_subnets = ["10.0.0.0/20"]
}

resource "aws_s3_bucket" "default" {
  for_each = toset(["localonly", "vpcendpointonly", "both"])

  bucket_prefix = each.key
}

resource "aws_vpc_endpoint" "s3" {
  vpc_endpoint_type = "Gateway"
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-1.s3"
  # The route to the VPC endpoint is automatically added
  # to the route table when the endpoint is created.
  route_table_ids = [module.vpc.private_route_table_ids[0]]
}

resource "aws_vpc_endpoint_policy" "name" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  policy          = <<EOF
  {
    "Version":"2012-10-17",
    "Statement":[
    {
        "Effect":"Allow",
        "Principal": "*",
        "Action": "s3:*",
        "Resource":[ 
          "${aws_s3_bucket.default["vpcendpointonly"].arn}/*",
          "${aws_s3_bucket.default["both"].arn}/*"
        ]
    },
    {
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : ["s3:ListBucket", "s3:DeleteBucketPolicy"],
        "Resource" : [
          "${aws_s3_bucket.default["vpcendpointonly"].arn}",
          "${aws_s3_bucket.default["both"].arn}"
        ]
    },
    {
        "Effect" : "Allow",
        "Principal": "*",
        "Action":[
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ],
        "Resource" : "*"
    }
    ]
}
  EOF
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "InstanceSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
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

resource "aws_iam_role" "instance_role" {
  name_prefix = "S3ReadOnlyInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Allow the EC2 instance to delete S3 bucket policy
# to allow `terraform destroy` to succeed.
resource "aws_iam_role_policy" "s3_readonly" {
  name_prefix = "S3DeleteBucketPolicy"
  role        = aws_iam_role.instance_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:DeleteBucketPolicy",
      ],
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_instance_profile" "default" {
  name_prefix = "S3ReadOnlyInstanceProfile"
  role        = aws_iam_role.instance_role.id
}

resource "aws_instance" "default" {
  ami                    = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.instance_sg.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.default.name
}

resource "aws_ec2_instance_connect_endpoint" "default" {
  subnet_id          = module.vpc.private_subnets[0]
  security_group_ids = [module.instance_sg.security_group_id]
}

# Prevent s3:ListBucket action from anywhere apart from
# the VPC gateway endpoint.
#
# This one is a bit tricky because after you applied the policy,
# you can't run Terraform destroy due to the lack of ListBucket
# access. To destroy successfully, run outputs.runBeforeDestroyUsingEC2Instance
# before running `terraform destroy`.
resource "aws_s3_bucket_policy" "vpc_endpoint_only" {
  bucket = aws_s3_bucket.default["vpcendpointonly"].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "Policy1415115909152",
  "Statement": [
    {
      "Sid": "Access-to-specific-VPCE-only",
      "Principal": "*",
      "Action": "s3:ListBucket",
      "Effect": "Deny",
      "Resource": [
        "${aws_s3_bucket.default["vpcendpointonly"].arn}"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:sourceVpce": "${aws_vpc_endpoint.s3.id}"
        }
      }
    }
  ]
}
  EOF
}

output "s3_buckets" {
  value = {
    vpcEndpointOnly = aws_s3_bucket.default["vpcendpointonly"].bucket
    localOnly       = aws_s3_bucket.default["localonly"].bucket
    both            = aws_s3_bucket.default["both"].bucket
  }
}

output "commands" {
  value = {
    runBeforeDestroyUsingEC2Instance = "aws s3api delete-bucket-policy --bucket ${aws_s3_bucket.default["vpcendpointonly"].bucket}"
  }
}

# TEST:
#
# - Run `aws s3 ls s3://{bucketName}` for each of the provided buckets locally and inside
# provided EC2 instance. You will see that `vpcendpointonly*` bucket can only be listed
# on the EC2 instance, `localonly*` bucket can only be listed locally and `both*` can be
# listed on... well, both.
