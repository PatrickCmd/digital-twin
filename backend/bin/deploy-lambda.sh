#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FUNCTION_NAME="twin-api"
RUNTIME="python3.12"
ARCHITECTURE="x86_64"
HANDLER="lambda_handler.handler"
TIMEOUT=60
MEMORY_SIZE=512
ZIP_FILE="lambda-deployment.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"

# Environment variables for the Lambda function
# OPENAI_API_KEY is read from the local .env or environment
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
S3_BUCKET="${S3_BUCKET:-twin-memory-${AWS_ACCOUNT_ID}}"

if [[ -z "$OPENAI_API_KEY" ]]; then
  # Try loading from .env files
  for envfile in "$BACKEND_DIR/.env" "$BACKEND_DIR/../.env"; do
    if [[ -f "$envfile" ]]; then
      val=$(grep -E '^OPENAI_API_KEY=' "$envfile" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
      if [[ -n "$val" ]]; then
        OPENAI_API_KEY="$val"
        break
      fi
    fi
  done
fi

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "ERROR: OPENAI_API_KEY not found. Set it in your environment or in a .env file."
  exit 1
fi

echo "=== Deploying Lambda Function (profile: $AWS_PROFILE, region: $AWS_REGION) ==="

# Step 1: Check that the zip file exists
echo ""
echo "--- Checking deployment package ---"
if [[ ! -f "$BACKEND_DIR/$ZIP_FILE" ]]; then
  echo "ERROR: $ZIP_FILE not found in $BACKEND_DIR"
  echo "Run 'uv run deploy.py' in the backend directory first."
  exit 1
fi
ZIP_SIZE=$(du -h "$BACKEND_DIR/$ZIP_FILE" | cut -f1)
echo "Found $ZIP_FILE ($ZIP_SIZE)"

# Step 2: Get or create the Lambda execution role
echo ""
echo "--- Ensuring Lambda execution role ---"
ROLE_NAME="${FUNCTION_NAME}-role"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" --query 'Role.Arn' --output text 2>/dev/null || true)

if [[ -z "$ROLE_ARN" || "$ROLE_ARN" == "None" ]]; then
  echo "Creating execution role: $ROLE_NAME"
  ASSUME_ROLE_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": { "Service": "lambda.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }
    ]
  }'
  ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$ASSUME_ROLE_POLICY" \
    --profile "$AWS_PROFILE" \
    --query 'Role.Arn' --output text)

  # Attach basic Lambda execution policy
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
    --profile "$AWS_PROFILE"

  echo "Waiting for role to propagate..."
  sleep 10
else
  echo "Role '$ROLE_NAME' already exists: $ROLE_ARN"
fi

# Step 3: Create or update the Lambda function
echo ""
echo "--- Creating/updating Lambda function: $FUNCTION_NAME ---"
EXISTING=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true)

if [[ -z "$EXISTING" ]]; then
  echo "Creating new Lambda function..."

  ZIP_SIZE_BYTES=$(stat -f%z "$BACKEND_DIR/$ZIP_FILE" 2>/dev/null || stat -c%s "$BACKEND_DIR/$ZIP_FILE")
  if (( ZIP_SIZE_BYTES > 50000000 )); then
    # Upload via S3 for large packages (>50MB)
    echo "Package is large, uploading via S3..."
    DEPLOY_BUCKET="twin-deploy-$(date +%s)"
    aws s3 mb "s3://$DEPLOY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
    aws s3 cp "$BACKEND_DIR/$ZIP_FILE" "s3://$DEPLOY_BUCKET/$ZIP_FILE" --profile "$AWS_PROFILE" --region "$AWS_REGION"

    aws lambda create-function \
      --function-name "$FUNCTION_NAME" \
      --runtime "$RUNTIME" \
      --architectures "$ARCHITECTURE" \
      --role "$ROLE_ARN" \
      --handler "$HANDLER" \
      --timeout "$TIMEOUT" \
      --memory-size "$MEMORY_SIZE" \
      --code "S3Bucket=$DEPLOY_BUCKET,S3Key=$ZIP_FILE" \
      --environment "Variables={OPENAI_API_KEY=$OPENAI_API_KEY,CORS_ORIGINS=*,USE_S3=true,S3_BUCKET=$S3_BUCKET}" \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION"

    # Clean up temp bucket
    echo "Cleaning up temporary S3 bucket..."
    aws s3 rm "s3://$DEPLOY_BUCKET/$ZIP_FILE" --profile "$AWS_PROFILE" --region "$AWS_REGION"
    aws s3 rb "s3://$DEPLOY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
  else
    # Direct upload for smaller packages
    aws lambda create-function \
      --function-name "$FUNCTION_NAME" \
      --runtime "$RUNTIME" \
      --architectures "$ARCHITECTURE" \
      --role "$ROLE_ARN" \
      --handler "$HANDLER" \
      --timeout "$TIMEOUT" \
      --memory-size "$MEMORY_SIZE" \
      --zip-file "fileb://$BACKEND_DIR/$ZIP_FILE" \
      --environment "Variables={OPENAI_API_KEY=$OPENAI_API_KEY,CORS_ORIGINS=*,USE_S3=true,S3_BUCKET=$S3_BUCKET}" \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION"
  fi

  echo "Lambda function created."
else
  echo "Function already exists, updating code and configuration..."

  # Update function code
  ZIP_SIZE_BYTES=$(stat -f%z "$BACKEND_DIR/$ZIP_FILE" 2>/dev/null || stat -c%s "$BACKEND_DIR/$ZIP_FILE")
  if (( ZIP_SIZE_BYTES > 50000000 )); then
    DEPLOY_BUCKET="twin-deploy-$(date +%s)"
    aws s3 mb "s3://$DEPLOY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
    aws s3 cp "$BACKEND_DIR/$ZIP_FILE" "s3://$DEPLOY_BUCKET/$ZIP_FILE" --profile "$AWS_PROFILE" --region "$AWS_REGION"

    aws lambda update-function-code \
      --function-name "$FUNCTION_NAME" \
      --s3-bucket "$DEPLOY_BUCKET" \
      --s3-key "$ZIP_FILE" \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION"

    aws s3 rm "s3://$DEPLOY_BUCKET/$ZIP_FILE" --profile "$AWS_PROFILE" --region "$AWS_REGION"
    aws s3 rb "s3://$DEPLOY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
  else
    aws lambda update-function-code \
      --function-name "$FUNCTION_NAME" \
      --zip-file "fileb://$BACKEND_DIR/$ZIP_FILE" \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION"
  fi

  # Wait for code update to complete before updating config
  echo "Waiting for code update to complete..."
  aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

  # Update function configuration
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler "$HANDLER" \
    --timeout "$TIMEOUT" \
    --memory-size "$MEMORY_SIZE" \
    --environment "Variables={OPENAI_API_KEY=$OPENAI_API_KEY,CORS_ORIGINS=*,USE_S3=true,S3_BUCKET=$S3_BUCKET}" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

  echo "Lambda function updated."
fi

# Wait for function to be active
echo ""
echo "--- Waiting for function to become active ---"
aws lambda wait function-active-v2 \
  --function-name "$FUNCTION_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
echo "Function is active."

# Summary
echo ""
echo "=== Lambda Deployment Complete ==="
echo "Function: $FUNCTION_NAME"
echo "Runtime:  $RUNTIME"
echo "Handler:  $HANDLER"
echo "Timeout:  ${TIMEOUT}s"
echo "Region:   $AWS_REGION"
echo ""
echo "Environment variables set:"
echo "  OPENAI_API_KEY = (hidden)"
echo "  CORS_ORIGINS   = *"
echo "  USE_S3         = true"
echo "  S3_BUCKET      = $S3_BUCKET"
