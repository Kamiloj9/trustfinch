terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }
  }

  # Configure this during init, e.g. terraform init -backend-config=backend.hcl.
  # Backend credentials must be short-lived and are never stored in this repo.
  backend "s3" {}
}
