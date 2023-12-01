
provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "instance_sg" {
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

  availability_zones = ["us-east-1a"]

  launch_template {
    id = aws_launch_template.default.id
  }
}

resource "aws_autoscaling_policy" "default" {
  name                   = "HighCpu"
  autoscaling_group_name = aws_autoscaling_group.default.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 20.0
  }
}

