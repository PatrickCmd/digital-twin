#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FUNCTION_NAME="twin-api"
LAMBDA_ROLE_NAME="${FUNCTION_NAME}-role"
API_NAME="twin-api-gateway"
DISTRIBUTION_COMMENT="twin-distribution"
MEMORY_BUCKET="twin-memory-${AWS_ACCOUNT_ID}"
FRONTEND_BUCKET="twin-frontend-${AWS_ACCOUNT_ID}"
GROUP_NAME="TwinAccess"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: AWS_ACCOUNT_ID is not set."
  echo "Set it in your .env file or export it: export AWS_ACCOUNT_ID=123456789012"
  exit 1
fi

echo "============================================"
echo "  Digital Twin AWS Teardown"
echo "============================================"
echo ""
echo "This will DELETE the following resources:"
echo "  - CloudFront distribution ($DISTRIBUTION_COMMENT)"
echo "  - API Gateway ($API_NAME)"
echo "  - Lambda function ($FUNCTION_NAME)"
echo "  - Lambda execution role ($LAMBDA_ROLE_NAME)"
echo "  - S3 bucket ($MEMORY_BUCKET) + all contents"
echo "  - S3 bucket ($FRONTEND_BUCKET) + all contents"
echo "  - IAM group ($GROUP_NAME)"
echo ""
read -p "Are you sure? Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""

# ---- 1. CloudFront Distribution ----
echo "=== 1/7 CloudFront Distribution ==="
DIST_ID=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='${DISTRIBUTION_COMMENT}'].Id | [0]" \
  --output text 2>/dev/null || true)

if [[ -n "$DIST_ID" && "$DIST_ID" != "None" ]]; then
  # Get current config and ETag
  DIST_CONFIG_RESPONSE=$(aws cloudfront get-distribution-config \
    --id "$DIST_ID" \
    --profile "$AWS_PROFILE" \
    --output json)

  ETAG=$(echo "$DIST_CONFIG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['ETag'])")
  IS_ENABLED=$(echo "$DIST_CONFIG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['DistributionConfig']['Enabled'])")

  if [[ "$IS_ENABLED" == "True" ]]; then
    echo "Disabling distribution $DIST_ID (must be disabled before deletion)..."
    DISABLED_CONFIG=$(echo "$DIST_CONFIG_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
config = data['DistributionConfig']
config['Enabled'] = False
print(json.dumps(config))
")
    ETAG=$(aws cloudfront update-distribution \
      --id "$DIST_ID" \
      --distribution-config "$DISABLED_CONFIG" \
      --if-match "$ETAG" \
      --profile "$AWS_PROFILE" \
      --query 'ETag' --output text)
    echo "Disabled. Waiting for deployment (this can take several minutes)..."
    aws cloudfront wait distribution-deployed \
      --id "$DIST_ID" \
      --profile "$AWS_PROFILE"
    echo "Distribution deployed in disabled state."
  fi

  echo "Deleting distribution $DIST_ID..."
  # Re-fetch ETag after waiting
  ETAG=$(aws cloudfront get-distribution-config \
    --id "$DIST_ID" \
    --profile "$AWS_PROFILE" \
    --query 'ETag' --output text)
  aws cloudfront delete-distribution \
    --id "$DIST_ID" \
    --if-match "$ETAG" \
    --profile "$AWS_PROFILE"
  echo "CloudFront distribution deleted."
else
  echo "No distribution found, skipping."
fi
echo ""

# ---- 2. API Gateway ----
echo "=== 2/7 API Gateway ==="
API_ID=$(aws apigatewayv2 get-apis \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text 2>/dev/null || true)

if [[ -n "$API_ID" && "$API_ID" != "None" ]]; then
  echo "Deleting API Gateway $API_NAME ($API_ID)..."
  aws apigatewayv2 delete-api \
    --api-id "$API_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"
  echo "API Gateway deleted."
else
  echo "No API Gateway found, skipping."
fi
echo ""

# ---- 3. Lambda Function ----
echo "=== 3/7 Lambda Function ==="
if aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$AWS_PROFILE" --region "$AWS_REGION" &>/dev/null; then
  echo "Deleting Lambda function $FUNCTION_NAME..."
  aws lambda delete-function \
    --function-name "$FUNCTION_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"
  echo "Lambda function deleted."
else
  echo "No Lambda function found, skipping."
fi
echo ""

# ---- 4. Lambda Execution Role ----
echo "=== 4/7 Lambda Execution Role ==="
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
  echo "Detaching policies from $LAMBDA_ROLE_NAME..."
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$LAMBDA_ROLE_NAME" \
    --profile "$AWS_PROFILE" \
    --query 'AttachedPolicies[].PolicyArn' --output text)

  for policy_arn in $ATTACHED_POLICIES; do
    echo "  Detaching: $(basename "$policy_arn")"
    aws iam detach-role-policy \
      --role-name "$LAMBDA_ROLE_NAME" \
      --policy-arn "$policy_arn" \
      --profile "$AWS_PROFILE"
  done

  echo "Deleting role $LAMBDA_ROLE_NAME..."
  aws iam delete-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --profile "$AWS_PROFILE"
  echo "Lambda execution role deleted."
else
  echo "No execution role found, skipping."
fi
echo ""

# ---- 5. S3 Memory Bucket ----
echo "=== 5/7 S3 Memory Bucket ==="
if aws s3api head-bucket --bucket "$MEMORY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null; then
  echo "Emptying and deleting $MEMORY_BUCKET..."
  aws s3 rm "s3://$MEMORY_BUCKET" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION"
  aws s3api delete-bucket --bucket "$MEMORY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
  echo "Memory bucket deleted."
else
  echo "No memory bucket found, skipping."
fi
echo ""

# ---- 6. S3 Frontend Bucket ----
echo "=== 6/7 S3 Frontend Bucket ==="
if aws s3api head-bucket --bucket "$FRONTEND_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null; then
  echo "Emptying and deleting $FRONTEND_BUCKET..."
  aws s3 rm "s3://$FRONTEND_BUCKET" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION"
  aws s3api delete-bucket --bucket "$FRONTEND_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION"
  echo "Frontend bucket deleted."
else
  echo "No frontend bucket found, skipping."
fi
echo ""

# ---- 7. IAM Group ----
echo "=== 7/7 IAM Group ==="
if aws iam get-group --group-name "$GROUP_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
  echo "Removing users from $GROUP_NAME..."
  GROUP_USERS=$(aws iam get-group \
    --group-name "$GROUP_NAME" \
    --profile "$AWS_PROFILE" \
    --query 'Users[].UserName' --output text)

  for user in $GROUP_USERS; do
    echo "  Removing user: $user"
    aws iam remove-user-from-group \
      --group-name "$GROUP_NAME" \
      --user-name "$user" \
      --profile "$AWS_PROFILE"
  done

  echo "Detaching policies from $GROUP_NAME..."
  GROUP_POLICIES=$(aws iam list-attached-group-policies \
    --group-name "$GROUP_NAME" \
    --profile "$AWS_PROFILE" \
    --query 'AttachedPolicies[].PolicyArn' --output text)

  for policy_arn in $GROUP_POLICIES; do
    echo "  Detaching: $(basename "$policy_arn")"
    aws iam detach-group-policy \
      --group-name "$GROUP_NAME" \
      --policy-arn "$policy_arn" \
      --profile "$AWS_PROFILE"
  done

  echo "Deleting group $GROUP_NAME..."
  aws iam delete-group \
    --group-name "$GROUP_NAME" \
    --profile "$AWS_PROFILE"
  echo "IAM group deleted."
else
  echo "No IAM group found, skipping."
fi

echo ""
echo "============================================"
echo "  Teardown Complete"
echo "============================================"
echo "All Digital Twin AWS resources have been removed."
