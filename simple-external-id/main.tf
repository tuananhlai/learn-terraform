provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "default" {
  bucket_prefix = "sei-test-"
}

resource "aws_s3_object" "default" {
  bucket       = aws_s3_bucket.default.id
  key          = "image.png"
  source       = "20240208221933.png"
  content_type = "image/png"
}

# Why is External ID necessary?
# https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html
resource "aws_iam_role" "default" {
  name_prefix = "sei-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.target_aws_account_id
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "default" {
  role = aws_iam_role.default.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*",
          "s3:Describe*",
        ]
        Resource = [
          "${aws_s3_bucket.default.arn}",
          "${aws_s3_bucket.default.arn}/*"
        ]
      }
    ]
  })
}

output "commands" {
  value = {
    # After running assume-role command, you will be given temporary credentials including
    # access key, secret key, and session token. Export them as environment variables
    # to finish assuming the role.
    # - AWS_ACCESS_KEY_ID
    # - AWS_SECRET_ACCESS_KEY
    # - AWS_SESSION_TOKEN
    assume_role = "aws sts assume-role --role-arn ${aws_iam_role.default.arn} --role-session-name testuser --external-id ${var.external_id}"
    ls_objects  = "aws s3 ls ${aws_s3_bucket.default.bucket}"
  }
}
