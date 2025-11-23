terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.22.1"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.3.2"
    }
  }
}

data "aws_caller_identity" "current" {}
