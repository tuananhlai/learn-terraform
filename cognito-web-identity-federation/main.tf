provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "app" {
  bucket_prefix = "cwi-app-"
}

resource "aws_s3_bucket" "patchesprivate" {
  bucket_prefix = "cwi-patchesprivate-"
}

resource "aws_s3_bucket_cors_configuration" "patchesprivate" {
  bucket = aws_s3_bucket.patchesprivate.bucket

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
  }
}

// Disable block public access
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.bucket
}

resource "aws_s3_bucket_website_configuration" "app" {
  bucket = aws_s3_bucket.app.bucket
  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.bucket
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.app.arn}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "patchesprivate" {
  name_prefix = "cwi-patchesprivate-bucket-readonly-"
  path        = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [aws_s3_bucket.patchesprivate.arn, "${aws_s3_bucket.patchesprivate.arn}/*"]
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    target_origin_id       = aws_s3_bucket.app.bucket
    viewer_protocol_policy = "https-only"
    cached_methods         = ["GET", "HEAD"]
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
  }

  origin {
    domain_name = aws_s3_bucket.app.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.app.bucket
    // TODO: this config causes CloudFront to be modified every time
    // Terraform is applied.
    s3_origin_config {
      origin_access_identity = ""
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
}

resource "aws_cognito_identity_pool" "default" {
  identity_pool_name = "cwi-identity-pool"

  allow_unauthenticated_identities = false

  supported_login_providers = {
    "accounts.google.com" = var.google_app_client_id
  }
}

data "aws_iam_policy_document" "cognito_identity_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.default.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

// The role to be assigned to authenticated users.
resource "aws_iam_role" "cognito_authenticated" {
  name               = "cwi-cognito-authenticated"
  assume_role_policy = data.aws_iam_policy_document.cognito_identity_assume_role.json
}

// Allow authenticated users to access the private image bucket.
resource "aws_iam_role_policy_attachment" "cognito_authenticated_patchesprivate" {
  role       = aws_iam_role.cognito_authenticated.id
  policy_arn = aws_iam_policy.patchesprivate.arn
}

resource "aws_cognito_identity_pool_roles_attachment" "default" {
  identity_pool_id = aws_cognito_identity_pool.default.id

  roles = {
    "authenticated" = aws_iam_role.cognito_authenticated.arn
  }
}

resource "aws_s3_object" "indexhtml" {
  bucket = aws_s3_bucket.app.bucket
  key    = "index.html"
  content = templatefile("${path.module}/appbucket/index.html.tftpl", {
    google_app_client_id = var.google_app_client_id
  })
  // if content_type is not set, requests to static website
  // will use application/octet-stream
  content_type = "text/html"
}

resource "aws_s3_object" "scriptsjs" {
  bucket = aws_s3_bucket.app.bucket
  key    = "scripts.js"
  content = templatefile("${path.module}/appbucket/scripts.js.tftpl", {
    patchesprivate_bucket_name = aws_s3_bucket.patchesprivate.bucket
    cognito_identity_pool_id   = aws_cognito_identity_pool.default.id
  })
}

resource "aws_s3_object" "patchesprivate" {
  for_each = fileset(path.module, "patchesprivatebucket/*.jpg")

  key          = split("/", each.key)[1]
  source       = each.key
  etag         = filemd5(each.key)
  bucket       = aws_s3_bucket.patchesprivate.bucket
  content_type = "image/jpeg"
}

output "application_url" {
  value = aws_cloudfront_distribution.app.domain_name
}
