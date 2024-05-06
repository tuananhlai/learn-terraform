provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "default" {
  name_prefix        = "simple-eks-"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.default.name
}

locals {
  cidr = "10.16.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "simple-eks-vpc"
  cidr = local.cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = cidrsubnets(local.cidr, 4, 4)
}

resource "aws_eks_cluster" "default" {
  name = "simple-eks-cluster"

  vpc_config {
    subnet_ids = module.aws_vpc.private_subnets
  }

  role_arn   = aws_iam_role.default.arn
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}
