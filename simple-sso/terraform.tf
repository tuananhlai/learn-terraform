terraform {
  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "simple-sso-2"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "~> 5.0"
    }
  }
}

