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
  name_prefix        = "simple-eks-cluster-role-"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.default.name
}

locals {
  cidr    = "10.16.0.0/16"
  subnets = cidrsubnets(local.cidr, 4, 4, 4, 4)
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
  private_subnets = slice(local.subnets, 0, 2)
  public_subnets  = slice(local.subnets, 2, 4)

  map_public_ip_on_launch = true
}

data "aws_iam_policy_document" "node_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "simple-eks-node-role-"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "default" {
  name = "simple-eks-cluster"

  vpc_config {
    subnet_ids = module.aws_vpc.public_subnets
  }

  role_arn   = aws_iam_role.default.arn
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_eks_node_group" "default" {
  cluster_name           = aws_eks_cluster.default.name
  node_group_name_prefix = "simple-eks-node-group-"
  node_role_arn          = aws_iam_role.node.arn
  // NOTE: A single free tier instance is too small to hold the core service pods
  // and the example app. You will need to use a larger instance type or multiple
  // free tier instances.
  instance_types         = ["t3.medium"]
  // NOTE: The pods need to be deployed in the public subnet because... ?
  subnet_ids             = module.aws_vpc.public_subnets

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_worker_policy
  ]
}

output "cluster_name" {
  value = aws_eks_cluster.default.name
}
