provider "aws" {
  region = "us-east-1"
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
echo 'cowsay "Amazon Linux 2023 AMI - Animals4Life"' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd
EOF
  tags = {
    Name = "single_instance_with_extra"
  }
}
