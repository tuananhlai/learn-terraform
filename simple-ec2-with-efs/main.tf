provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                    = "Ec2WithEfsVpc"
  cidr                    = "10.0.0.0/16"
  azs                     = ["us-east-1a"]
  public_subnets          = ["10.0.16.0/20"]
  private_subnets         = ["10.0.32.0/20"]
  map_public_ip_on_launch = true
}

resource "aws_security_group" "instance_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    # Allow SSH and NFS protocol
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
}

resource "aws_efs_file_system" "default" {

}

resource "aws_efs_mount_target" "default" {
  file_system_id  = aws_efs_file_system.default.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.instance_sg.id]
}

resource "aws_iam_role" "instance_role" {
  name = "InstanceRole"
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

resource "aws_iam_instance_profile" "default" {
  name = "InstanceProfile"
  role = aws_iam_role.instance_role.id
}

resource "aws_instance" "instances" {
  for_each = toset(["instanceA", "instanceB"])

  # Wait until the EFS is mounted in its subnet
  # before creating the instances.
  depends_on = [aws_efs_mount_target.default]
  tags = {
    Name = each.key
  }
  ami                         = "ami-0230bd60aa48260c6" #Amazon Linux 2023
  instance_type               = "t2.micro"
  iam_instance_profile        = aws_iam_instance_profile.default.id
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  subnet_id                   = module.vpc.public_subnets[0]
  user_data                   = <<EOF
#!/bin/bash -xe

dnf -y install wget cowsay amazon-efs-utils

echo "#!/bin/sh" > /etc/update-motd.d/40-cow
echo 'cowsay "Hello World!"' >> /etc/update-motd.d/40-cow
chmod 755 /etc/update-motd.d/40-cow
update-motd

mkdir -p /mnt/efs
echo "${aws_efs_file_system.default.id}:/ /mnt/efs efs _netdev,tls,iam 0 0" >> /etc/fstab

# Function to mount EFS
mount_efs() {
    mount /mnt/efs
}

# Retry the mount command until it succeeds
until mount_efs; do
    echo "Retrying to mount EFS..."
    sleep 5
done
EOF
  user_data_replace_on_change = true
}


