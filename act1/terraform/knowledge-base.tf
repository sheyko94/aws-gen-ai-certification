locals {
  kb_vector_index_name = "policies"
  kb_name_prefix       = substr(var.lambda_function_name, 0, 16)
  kb_collection_name   = "${var.lambda_function_name}-kb"
}


# IAM role for Bedrock Knowledge Base
data "aws_iam_policy_document" "kb_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "kb_permissions" {
  statement {
    sid    = "S3ReadPolicyDocs"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      module.policy_documents_bucket.s3_bucket_arn,
      "${module.policy_documents_bucket.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "OpenSearchAccess"
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "BedrockEmbedModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel"
    ]
    resources = [var.kb_embeddings_model_arn]
  }
}

resource "aws_iam_role" "kb_role" {
  name               = "${var.lambda_function_name}-kb-role"
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}

resource "aws_iam_role_policy" "kb_role_policy" {
  name   = "${var.lambda_function_name}-kb-permissions"
  role   = aws_iam_role.kb_role.id
  policy = data.aws_iam_policy_document.kb_permissions.json
}

# OpenSearch Serverless collection for vector store
resource "aws_opensearchserverless_collection" "kb" {
  name = local.kb_collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}

resource "opensearch_index" "kb_vector_index" {
  name               = local.kb_vector_index_name
  number_of_shards   = "1"
  number_of_replicas = "0"

  # Enable vector search (k-NN)
  index_knn                      = true
  index_knn_algo_param_ef_search = "128"

  # Important: mappings must match your field_mapping in the KB
  mappings = <<-EOF
  {
    "properties": {
      "vector": {
        "type": "knn_vector",
        "dimension": 1024,
        "method": {
          "name": "hnsw",
          "engine": "faiss",
          "space_type": "l2",
          "parameters": {
            "m": 16,
            "ef_construction": 512,
            "ef_search": 512
          }
        }
      },
      "text": {
        "type": "text",
        "index": true
      },
      "metadata": {
        "type": "text",
        "index": false
      }
    }
  }
  EOF

  force_destroy = true

  depends_on = [
    aws_opensearchserverless_collection.kb
  ]
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.kb_name_prefix}-kbenc"
  type        = "encryption"
  description = "Encryption policy for KB vector collection"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.kb_collection_name}"]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.kb_name_prefix}-kbnet"
  type        = "network"
  description = "Network policy for KB vector collection"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.kb_collection_name}"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.kb_name_prefix}-kbdata"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection",
        Resource     = ["collection/${local.kb_collection_name}"],
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "index",
        Resource     = ["index/${local.kb_collection_name}/${local.kb_vector_index_name}"],
        Permission   = ["aoss:*"]
      }
    ],
    Principal = [
      aws_iam_role.kb_role.arn,            # Bedrock KB role
      data.aws_caller_identity.current.arn # IAM principal running Terraform
    ]
  }])
}

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "policies" {
  name     = local.kb_collection_name
  role_arn = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.kb_embeddings_model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = local.kb_vector_index_name
      field_mapping {
        vector_field   = "vector"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_access_policy.data,
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    opensearch_index.kb_vector_index
  ]
}

resource "aws_bedrockagent_data_source" "policy_s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.policies.id
  name              = "${local.kb_name_prefix}-pol-s3"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = module.policy_documents_bucket.s3_bucket_arn
    }
  }
}
