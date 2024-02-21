terraform {
  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "serverless-pet-cuddle-o-tron"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "5.33.0"
    }
  }
}
