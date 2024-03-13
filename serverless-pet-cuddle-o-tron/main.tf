provider "aws" {
  region = "us-east-1"
}

// Stage 1 - Configure SES.

data "aws_sesv2_email_identity" "sender" {
  email_identity = var.sender_email_identity

  lifecycle {
    postcondition {
      condition     = self.verified_for_sending_status == true
      error_message = "sender email identity must be verified."
    }
  }
}

data "aws_sesv2_email_identity" "receiver" {
  email_identity = var.receiver_email_identity

  lifecycle {
    postcondition {
      condition     = self.verified_for_sending_status == true
      error_message = "receiver email identity must be verified."
    }
  }
}

// Stage 2 - Configure email_reminder lambda function.
resource "aws_iam_role" "lambda_execution_role" {
  name_prefix = "lambda_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatchlogs" {
  name_prefix = "cloudwatchlogs"
  role        = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ],
      Resource = ["arn:aws:logs:*:*:*"]
    }]
  })
}

resource "aws_iam_role_policy" "snsandsespermissions" {
  name_prefix = "snsandsespermissions"
  role        = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow",
      Action = [
        "ses:*",
        "sns:*",
        "states:*",
      ],
      Resource = ["*"]
    }]
  })
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/email_reminder.py"
  output_path = "${path.module}/tmp/email_reminder.zip"
}

resource "aws_lambda_function" "default" {
  function_name = "email_reminder_lambda"
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = data.archive_file.lambda_function.output_path
  // Trigger code upload when it is changed.
  source_code_hash = data.archive_file.lambda_function.output_base64sha256

  environment {
    variables = {
      "FROM_EMAIL_ADDRESS" = data.aws_sesv2_email_identity.sender.email_identity
    }
  }
}

// Stage 3 - Implement and Configure State Machine.

resource "aws_iam_role" "states" {
  name_prefix        = "states_execution_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatchlogs_policy" {
  name_prefix = "cloudwatchlogs"
  role        = aws_iam_role.states.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "invokelambda_sns_policy" {
  name_prefix = "invokelambda_sns"
  role        = aws_iam_role.states.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "sns:*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "states" {
  name_prefix = "pet-cuddle-o-tron-"
}

resource "aws_sfn_state_machine" "default" {
  name_prefix = "pet-cuddle-o-tron-states"
  role_arn    = aws_iam_role.states.arn

  definition = <<EOF
{
  "Comment": "Pet Cuddle-o-Tron - using Lambda for email.",
  "StartAt": "Timer",
  "States": {
    "Timer": {
      "Type": "Wait",
      "SecondsPath": "$.waitSeconds",
      "Next": "Email"
    },
    "Email": {
      "Type" : "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.default.arn}",
        "Payload": {
          "Input.$": "$"
        }
      },
      "Next": "NextState"
    },
    "NextState": {
      "Type": "Pass",
      "End": true
    }
  }
}
  EOF
  logging_configuration {
    level           = "ALL"
    log_destination = "${aws_cloudwatch_log_group.states.arn}:*"
  }
}

// Stage 4 - API Gateway and Application Lambda.

data "archive_file" "api_lambda" {
  type        = "zip"
  source_file = "${path.module}/api_lambda.py"
  output_path = "${path.module}/tmp/api_lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "api_lambda"
  runtime       = "python3.12"
  handler       = "api_lambda.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = data.archive_file.api_lambda.output_path
  // Trigger code upload when it is changed.
  source_code_hash = data.archive_file.api_lambda.output_base64sha256

  environment {
    variables = {
      "SM_ARN" = aws_sfn_state_machine.default.arn
    }
  }
}

resource "aws_api_gateway_rest_api" "petcuddleotron" {
  name = "petcuddleotron"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "petcuddleotron" {
  rest_api_id = aws_api_gateway_rest_api.petcuddleotron.id
  parent_id   = aws_api_gateway_rest_api.petcuddleotron.root_resource_id
  path_part   = "petcuddleotron"
}

// Create an OPTIONS method to allow CORS.

resource "aws_api_gateway_method" "petcuddleotron_options" {
  rest_api_id   = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id   = aws_api_gateway_resource.petcuddleotron.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "petcuddleotron_options_response" {
  rest_api_id = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id = aws_api_gateway_resource.petcuddleotron.id
  http_method = aws_api_gateway_method.petcuddleotron_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id = aws_api_gateway_resource.petcuddleotron.id
  http_method = aws_api_gateway_method.petcuddleotron_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id = aws_api_gateway_resource.petcuddleotron.id
  http_method = aws_api_gateway_method.petcuddleotron_options.http_method
  status_code = aws_api_gateway_method_response.petcuddleotron_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'*'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_method" "petcuddleotron_post" {
  rest_api_id   = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id   = aws_api_gateway_resource.petcuddleotron.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "petcuddleotron_post" {
  rest_api_id             = aws_api_gateway_rest_api.petcuddleotron.id
  resource_id             = aws_api_gateway_resource.petcuddleotron.id
  http_method             = aws_api_gateway_method.petcuddleotron_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "email_reminder" {
  statement_id  = "AllowAPIGateWayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.petcuddleotron.execution_arn}/*"
}

resource "aws_api_gateway_deployment" "default" {
  depends_on  = [aws_api_gateway_integration.options_integration, aws_api_gateway_integration.petcuddleotron_post]
  rest_api_id = aws_api_gateway_rest_api.petcuddleotron.id
  stage_name  = "prod"
}

// Stage 5 - Serverless Application Frontend.

resource "aws_s3_bucket" "petcuddleotron" {
  bucket_prefix = "pet-cuddle-o-tron-"
}

// Disable block public access
resource "aws_s3_bucket_public_access_block" "petcuddleotron" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
}

resource "aws_s3_bucket_policy" "petcuddleotron" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.petcuddleotron.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "petcuddleotron" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_object" "indexhtml" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  key    = "index.html"
  source = "frontend/index.html"
  etag   = filemd5("frontend/index.html")
  // if content_type is not set, requests to static website
  // will use application/octet-stream
  content_type = "text/html"
}

resource "aws_s3_object" "maincss" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  key    = "main.css"
  source = "frontend/main.css"
  etag   = filemd5("frontend/main.css")
}

resource "aws_s3_object" "whiskerspng" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  key    = "whiskers.png"
  source = "frontend/whiskers.png"
  etag   = filemd5("frontend/whiskers.png")
}

resource "aws_s3_object" "serverlessjs" {
  bucket = aws_s3_bucket.petcuddleotron.bucket
  key    = "serverless.js"
  content = templatefile("${path.module}/frontend/serverless.js.tftpl", {
    api_endpoint = "${aws_api_gateway_deployment.default.invoke_url}/${aws_api_gateway_resource.petcuddleotron.path_part}"
  })
}

output "values" {
  value = {
    send_email_website_url = aws_s3_bucket_website_configuration.petcuddleotron.website_endpoint
  }
}
