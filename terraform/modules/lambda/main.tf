# IAM role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda.name
}

# Least-privilege access: invoke the model, read/write the memory bucket,
# and (optionally) update the rate-limit table.
resource "aws_iam_role_policy" "lambda_app" {
  name = "${var.name_prefix}-lambda-app"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "InvokeBedrockModel"
          Effect = "Allow"
          Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream",
          ]
          # Cross-region inference profiles (global.* model ids) fan out to several
          # foundation-model ARNs, so the resource is kept open; the actions are not.
          Resource = "*"
        },
        {
          Sid      = "ListMemoryBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = var.s3_memory_bucket_arn
        },
        {
          Sid      = "ReadWriteMemoryObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "${var.s3_memory_bucket_arn}/*"
        },
      ],
      var.enable_rate_limit_table ? [
        {
          Sid      = "RateLimitTable"
          Effect   = "Allow"
          Action   = ["dynamodb:UpdateItem"]
          Resource = aws_dynamodb_table.rate_limit[0].arn
        },
      ] : []
    )
  })
}

# Optional per-client rate-limit counters (fixed window, TTL-expired).
# Off by default; enable with `enable_rate_limit_table = true`.
resource "aws_dynamodb_table" "rate_limit" {
  count = var.enable_rate_limit_table ? 1 : 0

  name         = "${var.name_prefix}-rate-limit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  tags         = var.common_tags

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

# Lambda function
resource "aws_lambda_function" "api" {
  filename         = var.deployment_package_path
  function_name    = "${var.name_prefix}-api"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_handler.handler"
  source_code_hash = filebase64sha256(var.deployment_package_path)
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = var.timeout
  memory_size      = 512
  tags             = var.common_tags

  environment {
    variables = merge(
      {
        CORS_ORIGINS              = var.cors_origins
        S3_BUCKET                 = var.s3_memory_bucket_id
        USE_S3                    = "true"
        BEDROCK_MODEL_ID          = var.bedrock_model_id
        MAX_MESSAGE_CHARS         = tostring(var.max_message_chars)
        MAX_SESSION_MESSAGES      = tostring(var.max_session_messages)
        RATE_LIMIT_REQUESTS       = tostring(var.rate_limit_requests)
        RATE_LIMIT_WINDOW_SECONDS = tostring(var.rate_limit_window_seconds)
      },
      var.enable_rate_limit_table ? { RATE_LIMIT_TABLE = aws_dynamodb_table.rate_limit[0].name } : {}
    )
  }

  depends_on = [aws_iam_role_policy.lambda_app]
}
