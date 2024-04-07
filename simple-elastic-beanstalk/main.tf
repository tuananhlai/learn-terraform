provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "default" {
  bucket_prefix = "seb-test-"
}

resource "aws_s3_object" "default" {
  bucket = aws_s3_bucket.default.id
  key    = "go.zip"
  source = "go.zip"
}

resource "aws_elastic_beanstalk_application" "default" {
  name = "seb-test"
}

resource "aws_elastic_beanstalk_application_version" "default" {
  name        = "seb-test-v1"
  application = aws_elastic_beanstalk_application.default.name
  bucket      = aws_s3_bucket.default.id
  key         = aws_s3_object.default.id
}

resource "aws_iam_role" "instance" {
  name_prefix = "seb-ec2-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "default" {
  name_prefix = "seb-ec2-instance-profile-"
  role = aws_iam_role.instance.name
}

resource "aws_elastic_beanstalk_environment" "default" {
  name                = "seb-test-env"
  application         = aws_elastic_beanstalk_application.default.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.0.5 running Go 1"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.default.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.micro"
  }
}
