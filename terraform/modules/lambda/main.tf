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

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  role       = aws_iam_role.lambda.name
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda.name
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
    variables = {
      CORS_ORIGINS     = var.cors_origins
      S3_BUCKET        = var.s3_memory_bucket_id
      USE_S3           = "true"
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
}
