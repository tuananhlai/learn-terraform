terraform {
  cloud {
    organization = "andy-learn-terraform"

    workspaces {
      name = "hybrid-dns"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "5.33.0"
    }
  }
}
