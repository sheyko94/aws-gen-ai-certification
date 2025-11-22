terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket = "aws-gen-ai-certification-terraform-state-igc"
    key    = "global/terraform.tfstate"
    region = "eu-central-1"
    encrypt = true
  }
}
