module "claim_documents_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = ">= 4.1.0"

  bucket        = var.claim_documents_bucket_name
  acl           = "public-read"
  force_destroy = true

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
}

module "policy_documents_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = ">= 4.1.0"

  bucket        = var.policy_documents_bucket_name
  acl           = "public-read"
  force_destroy = true

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
}

resource "aws_s3_bucket_notification" "policy_docs_notification" {
  bucket = module.policy_documents_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.policy_sync.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_policy_bucket_invoke
  ]
}

resource "aws_s3_bucket_notification" "claim_documents_notification" {
  bucket = module.claim_documents_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.claim_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_s3_invoke
  ]
}
