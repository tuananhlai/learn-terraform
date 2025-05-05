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
      protocol    = "all"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "all"
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
    name = "name"
    // Note that we must use an AMI optimized for ECS instead of
    // a general purpose AMI like the ones you see when launching a new EC2 instance.
    values = ["al2023-ami-ecs-hvm-*-kernel-6.1-x86_64"]
  }
}

// https://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html
resource "aws_iam_role" "ecs_ec2" {
  name = "simple-ecs-ec2-role"
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
  name_prefix = "simple-ecs-instance-profile"
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
      // Volumn size needs to be at least 30GB in order to use this AMI.
      volume_size = 30
      volume_type = "gp2"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-instance"
    }
  }

  // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_container_instance.html#linux-liw-advanced-details
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
  desired_capacity    = 2
  max_size            = 3

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
  // Because our task definition will use `awsvpc` network mode, `target_type` must be `ip`.
  //
  // > For services with tasks using the awsvpc network mode, when you create a target group
  // for your service, you must choose ip as the target type, not instance. This is because
  // tasks that use the awsvpc network mode are associated with an elastic network interface,
  // not an Amazon EC2 instance.
  //
  // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/alb.html
  target_type = "ip"

  health_check {
    path = "/"
  }
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

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.default.name
  }
}

// https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
resource "aws_iam_role" "ecs_execution" {
  name_prefix = "simple-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "default" {
  family             = "simple-ecs-task-definition"
  network_mode       = "awsvpc"
  cpu                = 256
  execution_role_arn = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name  = "nginx"
      image = "nginx:latest"
      // memory and cpu might be reduced for a better demo experience.
      // Because `t2.micro` instance only have ~1GB of RAM, setting
      // the memory as 512MB would make it difficult to deploy new tasks.
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

resource "aws_ecs_service" "default" {
  name            = "simple-ecs-service"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.default.arn
  desired_count   = 1

  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [module.instance_sg.security_group_id]
  }

  // the next two lines might not be necessary.
  force_new_deployment = true
  placement_constraints {
    type = "distinctInstance"
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.default.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "nginx"
    container_port   = 80
  }
}

// Trying opening output.lb_url in your browser. If you see the Nginx welcome page, you've successfully set up your ECS service.
output "default" {
  value = {
    lb_url                   = aws_lb.ecs.dns_name
    launch_template_ami_id   = data.aws_ami.amz_linux_2023.id
    launch_template_ami_name = data.aws_ami.amz_linux_2023.name
  }
}
