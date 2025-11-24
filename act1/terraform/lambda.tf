data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      module.claim_documents_bucket.s3_bucket_arn,
      "${module.claim_documents_bucket.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "BedrockKnowledgeBaseRetrieve"
    effect = "Allow"
    actions = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate"
    ]
    resources = [aws_bedrockagent_knowledge_base.policies.arn]
  }

  statement {
    sid    = "BedrockKnowledgeBaseIngest"
    effect = "Allow"
    actions = [
      "bedrock:StartIngestionJob"
    ]
    resources = [
      aws_bedrockagent_knowledge_base.policies.arn
    ]
  }

  statement {
    sid    = "MarketplaceSubscriptionCheck"
    effect = "Allow"
    actions = [
      "aws-marketplace:ViewSubscriptions",
      "aws-marketplace:Subscribe"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_lambda_function" "claim_processor" {
  function_name = var.lambda_function_name
  description   = "Processes claim documents from S3, invokes Bedrock, and writes _result objects back to S3."
  role          = aws_iam_role.lambda_role.arn

  filename         = "${path.module}/../lambda/build/libs/${var.lambda_function_name}.jar"
  source_code_hash = filebase64sha256("${path.module}/../lambda/build/libs/${var.lambda_function_name}.jar")

  handler = "com.example.claims.ClaimProcessorHandler::handleRequest"
  runtime = "java17"

  memory_size = 1024
  timeout     = 60

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.policies.id
    }
  }
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.claim_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.claim_documents_bucket.s3_bucket_arn
}

resource "aws_lambda_function" "policy_sync" {
  function_name = var.policy_sync_lambda_name
  description   = "Triggers Bedrock KB ingestion when a policy document is uploaded."
  role          = aws_iam_role.lambda_role.arn

  filename         = "${path.module}/../lambda/build/libs/${var.lambda_function_name}.jar"
  source_code_hash = filebase64sha256("${path.module}/../lambda/build/libs/${var.lambda_function_name}.jar")

  handler = "com.example.claims.PolicySyncHandler::handleRequest"
  runtime = "java17"

  memory_size = 512
  timeout     = 30

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.policies.id
      DATA_SOURCE_ID    = aws_bedrockagent_data_source.policy_s3.data_source_id
    }
  }
}

resource "aws_lambda_permission" "allow_policy_bucket_invoke" {
  statement_id  = "AllowPolicyBucketInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.policy_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.policy_documents_bucket.s3_bucket_arn
}
