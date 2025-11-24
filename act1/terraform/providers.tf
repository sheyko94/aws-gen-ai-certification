provider "aws" {
  region = var.aws_region
}

provider "opensearch" {
  # Uses the collection endpoint created by aws_opensearchserverless_collection.kb
  url               = aws_opensearchserverless_collection.kb.collection_endpoint
  healthcheck       = false
  aws_region        = var.aws_region
  sign_aws_requests = true
}
