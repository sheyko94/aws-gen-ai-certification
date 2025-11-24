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

variable "policy_documents_bucket_name" {
  description = "S3 bucket name that stores policy documents for the knowledge base."
  type        = string
  default     = "policy-documents-poc-igc"
}

variable "kb_embeddings_model_arn" {
  description = "Embeddings model ARN for the Bedrock knowledge base (e.g., arn:aws:bedrock:<region>::foundation-model/amazon.titan-embed-text-v2:0)."
  type        = string
  default     = "arn:aws:bedrock:eu-central-1::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "policy_sync_lambda_name" {
  description = "Lambda function name for KB ingestion sync."
  type        = string
  default     = "policy-sync-lambda"
}
