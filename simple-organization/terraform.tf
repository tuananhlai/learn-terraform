terraform {
  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "simple-organization"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "5.33.0"
    }
  }
}
