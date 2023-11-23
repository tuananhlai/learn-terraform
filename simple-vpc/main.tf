provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "simple_vpc" {
  tags = {
    Name = "SimpleVPC"
  }
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw_simple_vpc" {
}

resource "aws_subnet" "public_subnet" {
  tags = {
    Name = "PublicSubnet"
  }
  vpc_id            = aws_vpc.simple_vpc.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet" {
  tags = {
    Name = "PrivateSubnet"
  }
  vpc_id            = aws_vpc.simple_vpc.id
  cidr_block        = "10.0.32.0/20"
  availability_zone = "us-east-1a"
}

resource "aws_route_table" "public_route_table" {
  tags = {
    Name = "PublicRouteTable"
  }
  vpc_id = aws_vpc.simple_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_simple_vpc.id
  }
}

resource "aws_route_table_association" "associate_public_route_table" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet.id
}

resource "aws_internet_gateway_attachment" "attach_igw_to_simple_vpc" {
  internet_gateway_id = aws_internet_gateway.igw_simple_vpc.id
  vpc_id              = aws_vpc.simple_vpc.id
}

# Launch instances in public and private subnet.

resource "aws_security_group" "private_instance_sg" {
  tags = {
    Name = "PrivateInstanceSG"
  }

  vpc_id = aws_vpc.simple_vpc.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
  }
}

resource "aws_security_group" "public_instance_sg" {
  tags = {
    Name = "PublicInstanceSG"
  }

  vpc_id = aws_vpc.simple_vpc.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::0/0"]
  }
}

resource "aws_instance" "public_instance" {
  tags = {
    Name = "PublicInstance"
  }
  ami                         = "ami-0230bd60aa48260c6"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.public_instance_sg.id]
  associate_public_ip_address = true
}

# Private Instance can not be SSHed into, since we
# haven't set up Bastion Host or Session Manager.
resource "aws_instance" "private_instance" {
  tags = {
    Name = "PrivateInstance"
  }
  ami                         = "ami-0230bd60aa48260c6"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.private_instance_sg.id]
}

output "public_instance_private_ip_address" {
  value = aws_instance.public_instance.private_ip
}

output "private_instance_private_ip_address" {
  value = aws_instance.private_instance.private_ip
}
