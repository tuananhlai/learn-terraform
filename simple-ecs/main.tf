provider "aws" {
  region = "us-east-1"
}

locals {
  default_vpc_cidr = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                 = "simple-ecs-vpc"
  cidr                 = local.default_vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets       = cidrsubnets(local.default_vpc_cidr, 4, 4)
  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  vpc_id          = module.vpc.vpc_id
  name            = "simple-ecs-instance-sg"
  use_name_prefix = true

  // For demo purpose only. The ingress and egress rules should be much more restrictive in production.
  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
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

data "aws_ami" "amz_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-20*-kernel-6.1-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_iam_role" "ecs_ec2" {
  name = "SimpleECSEC2Role"
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

resource "aws_iam_role_policy_attachment" "ecs_ec2" {
  role       = aws_iam_role.ecs_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_ec2" {
  name_prefix = "SimpleECS"
  role        = aws_iam_role.ecs_ec2.id
}

resource "aws_ecs_cluster" "default" {
  name = "simple-ecs-cluster"
}

resource "aws_launch_template" "ecs_lt" {
  name_prefix            = "simple-ecs-launch-template"
  image_id               = data.aws_ami.amz_linux_2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [module.instance_sg.security_group_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_ec2.arn
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 10
      volume_type = "gp2"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-instance"
    }
  }

  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.default.name} >> /etc/ecs/ecs.config
    EOF
  )
}

resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix         = "simple-ecs-asg"
  vpc_zone_identifier = module.vpc.public_subnets
  min_size            = 0
  max_size            = 2

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_lb" "ecs" {
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.instance_sg.security_group_id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "ecs" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_lb_listener" "ecs" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

resource "aws_ecs_capacity_provider" "default" {
  name = "simple-ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "default" {
  cluster_name       = aws_ecs_cluster.default.name
  capacity_providers = [aws_ecs_capacity_provider.default.name]
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family       = "simple-ecs-task-definition"
  network_mode = "awsvpc"
  cpu          = 256

  container_definitions = jsonencode([
    {
      name      = "dockergs"
      image     = "public.ecr.aws/f9n5f1l7/dgs:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}
