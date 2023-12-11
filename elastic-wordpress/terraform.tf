terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "5.26.0"
    }
  }

  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "elastic-wordpress"
    }
  }
}


