provider "aws" {
  region = "us-east-1"
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

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

resource "aws_lambda_function" "default" {
  function_name = "echo_lambda_function"
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = data.archive_file.lambda_function.output_path
}

output "test_command" {
  # https://how.wtf/invalid-base64-error-lambda-aws-cli.html
  value = <<-EOF
    aws lambda invoke --function-name ${aws_lambda_function.default.function_name} --cli-binary-format raw-in-base64-out --payload '{"key": "value"}' /dev/stdout
  EOF
}
