provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "default" {
  name = "step-function-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "states.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "default" {
  name     = "default-state-machine"
  role_arn = aws_iam_role.default.arn

  definition = file("./simple-sfn.json")
}
