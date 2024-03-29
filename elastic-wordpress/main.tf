provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "ElasticWordpressVPC"
  cidr = "10.16.0.0/16"

  azs                     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets          = ["10.16.48.0/20", "10.16.112.0/20", "10.16.176.0/20"]
  public_subnet_names     = ["sn-pub-A", "sn-pub-B", "sn-pub-C"]
  private_subnets         = ["10.16.32.0/20", "10.16.96.0/20", "10.16.160.0/20"]
  private_subnet_names    = ["sn-app-A", "sn-app-B", "sn-app-C"]
  database_subnets        = ["10.16.16.0/20", "10.16.80.0/20", "10.16.144.0/20"]
  database_subnet_names   = ["sn-db-A", "sn-db-B", "sn-db-C"]
  map_public_ip_on_launch = true
  igw_tags = {
    Name = "igw-ElasticWordpressVPC"
  }
}

locals {
  db_user     = "a4lwordpressuser"
  db_password = "4n1m4l54L1f3"
  db_name     = "a4lwordpressdb"
}

resource "aws_db_instance" "wordpress" {
  identifier           = "a4lwordpress"
  instance_class       = "db.t2.micro"
  db_subnet_group_name = module.vpc.database_subnet_group_name
  username             = local.db_user
  password             = local.db_password
  db_name              = local.db_name
  engine               = "mysql"
  engine_version       = "8.0.32"
  skip_final_snapshot  = true
  allocated_storage    = 10
}

resource "aws_ssm_parameter" "wordpress" {
  for_each = {
    "dbUser" = {
      name        = "/A4L/Wordpress/DBUser"
      type        = "String"
      value       = local.db_user
      description = "Wordpress Database User"
    },
    "dbName" = {
      name        = "/A4L/Wordpress/DBName"
      type        = "String"
      value       = local.db_name
      description = "Wordpress Database Name"
    },
    "dbPassword" = {
      name        = "/A4L/Wordpress/DBPassword"
      type        = "SecureString"
      value       = local.db_password
      description = "Wordpress DB Password"
    },
    "dbRootPassword" = {
      name        = "/A4L/Wordpress/DBRootPassword"
      type        = "SecureString"
      value       = local.db_password
      description = "Wordpress DBRoot Password"
    },
    "dbEndpoint" = {
      name        = "/A4L/Wordpress/DBEndpoint"
      type        = "String"
      value       = aws_db_instance.wordpress.address # use hostname only to be true to the lab
      description = "Wordpress Endpoint Name"
    }
  }
  tier        = "Standard"
  name        = each.value.name
  type        = each.value.type
  value       = each.value.value
  description = each.value.description
}

resource "aws_efs_file_system" "default" {

}

resource "aws_efs_mount_target" "default" {
  for_each = {
    0 = module.vpc.private_subnets[0]
    1 = module.vpc.private_subnets[1]
    2 = module.vpc.private_subnets[2]
  }
  file_system_id = aws_efs_file_system.default.id
  subnet_id      = each.value
}

resource "aws_security_group" "lb_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::0/0"]
  }
}

resource "aws_alb" "default" {
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.lb_sg.id]
  internal        = false
}

resource "aws_alb_target_group" "default" {
  vpc_id   = module.vpc.vpc_id
  port     = 80
  protocol = "HTTP"
}

resource "aws_alb_listener" "default" {
  load_balancer_arn = aws_alb.default.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default.arn
  }
}

resource "aws_security_group" "instance_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::0/0"]
  }
}

resource "aws_launch_template" "default" {
  image_id               = "ami-0230bd60aa48260c6"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  user_data = base64encode(<<EOF
#!/bin/bash
dnf -y install wget cowsay nginx stress

echo "#!/bin/sh" > /etc/update-motd.d/40-cow
echo 'cowsay "Hello World!"' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd

PRIVATE_IP=$(hostname -I)

echo "<h1>Welcome to $PRIVATE_IP</h1>" > /usr/share/nginx/html/index.html

service nginx start
chkconfig nginx on
  EOF
  )
  update_default_version = true
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Worker"
    }
  }
}

resource "aws_autoscaling_group" "default" {
  min_size         = 1
  desired_capacity = 2
  max_size         = 3

  target_group_arns   = [aws_alb_target_group.default.arn]
  vpc_zone_identifier = module.vpc.public_subnets

  launch_template {
    id = aws_launch_template.default.id
  }
}

