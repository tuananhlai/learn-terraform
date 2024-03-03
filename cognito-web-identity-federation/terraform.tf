terraform {
  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "cognito-web-identity-federation"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "5.33.0"
    }
  }
}
