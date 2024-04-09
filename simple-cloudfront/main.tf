provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "default" {
  bucket_prefix = "scf-bucket-"
}

resource "aws_s3_object" "images" {
  for_each = fileset(path.module, "images/*.png")

  key          = "public/${split("/", each.key)[1]}"
  source       = each.key
  bucket       = aws_s3_bucket.default.bucket
  content_type = "image/png"
}

resource "aws_s3_object" "private_images" {
  for_each = fileset(path.module, "private-images/*.png")

  key          = "private/${split("/", each.key)[1]}"
  source       = each.key
  bucket       = aws_s3_bucket.default.bucket
  content_type = "image/png"
}

locals {
  s3_origin_id = aws_s3_bucket.default.bucket
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "scf-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_public_key" "default" {
  name        = "scf-public-key"
  encoded_key = file("keys/public_key.pem")
}

resource "aws_cloudfront_key_group" "default" {
  name  = "scf-key-group"
  items = [aws_cloudfront_public_key.default.id]
}

resource "aws_cloudfront_distribution" "default" {
  enabled = true

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  origin {
    domain_name              = aws_s3_bucket.default.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  # Require signed URLs or cookies for private content.
  ordered_cache_behavior {
    path_pattern           = "/private/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    trusted_key_groups     = [aws_cloudfront_key_group.default.id]
  }
}

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.default.bucket
  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": {
        "Sid": "AllowCloudFrontServicePrincipalReadOnly",
        "Effect": "Allow",
        "Principal": {
            "Service": "cloudfront.amazonaws.com"
        },
        "Action": "s3:GetObject",
        "Resource": "${aws_s3_bucket.default.arn}/*",
        "Condition": {
            "StringEquals": {
                "AWS:SourceArn": "${aws_cloudfront_distribution.default.arn}"
            }
        }
    }
  } 
  EOF
}

output "values" {
  value = {
    cloudfront_domain_name = aws_cloudfront_distribution.default.domain_name
    key_pair_id            = aws_cloudfront_public_key.default.id
  }
}
