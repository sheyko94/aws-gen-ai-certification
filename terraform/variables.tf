variable "aws_region" {
  description = "AWS region where the infrastructure will be provisioned."
  type        = string
  default     = "eu-central-1"
}

variable "claim_documents_bucket_name" {
  description = "S3 bucket name for claim documents (can be set via TF_VAR_claim_documents_bucket_name)."
  type        = string
  default     = "claim-documents-poc-igc"
}

variable "lambda_function_name" {
  description = "Lambda function name for claim document processing."
  type        = string
  default     = "claim-document-processor"
}
