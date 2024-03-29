provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "instance_role" {
  name = "S3ReadOnlyInstanceRole"
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
      },
    ]
  })
}

resource "aws_iam_role_policy" "s3_readonly" {
  name = "S3ReadOnlyPolicy"
  role = aws_iam_role.instance_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:Get*",
        "s3:List*",
        "s3:Describe*",
      ],
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_instance_profile" "default" {
  name = "S3ReadOnlyInstanceProfile"
  role = aws_iam_role.instance_role.id
}

resource "aws_security_group" "instance_sg" {
  name        = "InstanceSG"
  description = "test sg for terraform instance"
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all to port 80"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all to port 22"
  }
  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::0/0"]
  }
}

resource "aws_instance" "single_instance_with_extra" {
  ami                    = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type          = "t2.micro"
  availability_zone      = "us-east-1b"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  user_data              = <<EOF
#!/bin/bash

# Update the package manager
sudo yum update -y

# Install cowsay
sudo yum install -y cowsay

# Customize the Message of the Day (motd)
echo "#!/bin/sh" > /etc/update-motd.d/40-cow
echo 'cowsay "I am a cow."' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd
EOF
  tags = {
    Name = "single_instance_with_extra"
  }
  iam_instance_profile = aws_iam_instance_profile.default.id
}

resource "aws_ebs_volume" "instance_ebs" {
  availability_zone = "us-east-1b"
  size              = 10
  type              = "gp3"
}

resource "aws_volume_attachment" "attach_ebs_to_instance" {
  device_name = "/dev/xvdf"
  instance_id = aws_instance.single_instance_with_extra.id
  volume_id   = aws_ebs_volume.instance_ebs.id
}
