terraform {

  backend "s3" {
    bucket  = "aws-gen-ai-certification-terraform-state-igc"
    key     = "global/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }

}
