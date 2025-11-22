data "aws_caller_identity" "current" {}

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
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.claim_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.claim_documents_bucket.s3_bucket_arn
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
