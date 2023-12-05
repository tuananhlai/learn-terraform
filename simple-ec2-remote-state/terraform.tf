terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.7.0"
    }
  }

  backend "s3" {
    # Key needs to be different for EVERY terraform project.
    key = "global/single-ec2-remote-state/terraform.tfstate"

    bucket = "terraform-remote-state-198036150276"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt = true
  }
}
