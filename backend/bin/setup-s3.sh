#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FUNCTION_NAME="twin-api"
LAMBDA_ROLE_NAME="${FUNCTION_NAME}-role"

# Bucket names — use account ID as the unique suffix
MEMORY_BUCKET="twin-memory-${AWS_ACCOUNT_ID}"
FRONTEND_BUCKET="twin-frontend-${AWS_ACCOUNT_ID}"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: AWS_ACCOUNT_ID is not set."
  echo "Set it in your .env file or export it: export AWS_ACCOUNT_ID=123456789012"
  exit 1
fi

echo "=== Setting up S3 Buckets (profile: $AWS_PROFILE, region: $AWS_REGION) ==="

# ---- Step 1: Create Memory Bucket ----
echo ""
echo "--- Creating memory bucket: $MEMORY_BUCKET ---"
if aws s3api head-bucket --bucket "$MEMORY_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null; then
  echo "Bucket '$MEMORY_BUCKET' already exists, skipping."
else
  aws s3api create-bucket \
    --bucket "$MEMORY_BUCKET" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    $(if [[ "$AWS_REGION" != "us-east-1" ]]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)
  echo "Bucket '$MEMORY_BUCKET' created."
fi

# ---- Step 2: Update Lambda S3_BUCKET env var ----
echo ""
echo "--- Updating Lambda environment variable S3_BUCKET ---"
# Get current environment variables
CURRENT_ENV=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'Environment.Variables' \
  --output json 2>/dev/null || echo "{}")

# Update S3_BUCKET in the existing variables
UPDATED_ENV=$(echo "$CURRENT_ENV" | python3 -c "
import sys, json
env = json.load(sys.stdin)
env['S3_BUCKET'] = '$MEMORY_BUCKET'
print(json.dumps({'Variables': env}))
")

aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --environment "$UPDATED_ENV" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'FunctionName' --output text > /dev/null

echo "S3_BUCKET set to '$MEMORY_BUCKET'."

# ---- Step 3: Add S3 permissions to Lambda role ----
echo ""
echo "--- Attaching S3 permissions to Lambda role: $LAMBDA_ROLE_NAME ---"
aws iam attach-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
  --profile "$AWS_PROFILE"
echo "AmazonS3FullAccess attached to '$LAMBDA_ROLE_NAME'."

# ---- Step 4: Create Frontend Bucket ----
echo ""
echo "--- Creating frontend bucket: $FRONTEND_BUCKET ---"
if aws s3api head-bucket --bucket "$FRONTEND_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null; then
  echo "Bucket '$FRONTEND_BUCKET' already exists, skipping creation."
else
  aws s3api create-bucket \
    --bucket "$FRONTEND_BUCKET" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    $(if [[ "$AWS_REGION" != "us-east-1" ]]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)
  echo "Bucket '$FRONTEND_BUCKET' created."
fi

# Disable block public access
echo "Disabling Block Public Access..."
aws s3api put-public-access-block \
  --bucket "$FRONTEND_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"

# ---- Step 5: Enable Static Website Hosting ----
echo ""
echo "--- Enabling static website hosting on $FRONTEND_BUCKET ---"
aws s3 website "s3://$FRONTEND_BUCKET" \
  --index-document index.html \
  --error-document 404.html \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
echo "Static website hosting enabled."

# ---- Step 6: Set Bucket Policy for public read ----
echo ""
echo "--- Setting public read bucket policy ---"
BUCKET_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${FRONTEND_BUCKET}/*"
        }
    ]
}
EOF
)

aws s3api put-bucket-policy \
  --bucket "$FRONTEND_BUCKET" \
  --policy "$BUCKET_POLICY" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
echo "Public read policy applied."

# ---- Summary ----
WEBSITE_URL="http://${FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"

echo ""
echo "=== S3 Setup Complete ==="
echo ""
echo "Memory bucket:   $MEMORY_BUCKET"
echo "Frontend bucket:  $FRONTEND_BUCKET"
echo "Website URL:      $WEBSITE_URL"
echo ""
echo "Next steps:"
echo "  1. Build frontend:  cd frontend && npm run build"
echo "  2. Upload frontend: aws s3 sync out/ s3://$FRONTEND_BUCKET/ --delete --profile $AWS_PROFILE"
