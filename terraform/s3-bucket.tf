module "claim_documents_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = ">= 4.1.0"

  bucket = var.claim_documents_bucket_name
  acl    = "public-read"

  # Allow ACL usage (needed for public-read); some accounts default to ACLs disabled.
  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  versioning = {
    enabled = false
  }

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  force_destroy = true
}
