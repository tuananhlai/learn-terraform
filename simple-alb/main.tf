provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                    = "SimpleAlbVpc"
  cidr                    = "10.0.0.0/16"
  azs                     = ["us-east-1a", "us-east-1b"]
  public_subnets          = ["10.0.16.0/20", "10.0.32.0/20"]
  map_public_ip_on_launch = true
}

resource "aws_security_group" "instance_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_instance" "instances" {
  for_each = {
    "instanceA" = {
      subnet_id = module.vpc.public_subnets[0]
    }
    "instanceB" = {
      subnet_id = module.vpc.public_subnets[1]
    }
  }

  tags = {
    Name = each.key
  }
  ami                         = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  subnet_id                   = each.value.subnet_id
  user_data                   = <<EOF
#!/bin/bash
dnf -y install wget cowsay nginx

echo "#!/bin/sh" > /etc/update-motd.d/40-cow
echo 'cowsay "Hello World!"' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd

echo "<h1>Welcome to ${each.key}</h1>" > /usr/share/nginx/html/index.html

service nginx start
chkconfig nginx on
EOF
  user_data_replace_on_change = true
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

resource "aws_alb_target_group" "default" {
  vpc_id   = module.vpc.vpc_id
  port     = 80
  protocol = "HTTP"
}

resource "aws_alb_target_group_attachment" "attachments" {
  for_each = aws_instance.instances

  target_group_arn = aws_alb_target_group.default.arn
  target_id        = each.value.id
}

resource "aws_alb" "default" {
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.lb_sg.id]
  internal        = false
}

resource "aws_alb_listener" "default" {
  load_balancer_arn = aws_alb.default.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default.arn
  }
}
