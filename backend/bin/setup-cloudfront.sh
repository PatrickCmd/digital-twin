#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FUNCTION_NAME="twin-api"
FRONTEND_BUCKET="twin-frontend-${AWS_ACCOUNT_ID}"
DISTRIBUTION_COMMENT="twin-distribution"

# CachingOptimized managed cache policy ID (AWS-managed)
CACHING_OPTIMIZED_POLICY_ID="658327ea-f89d-4fab-a63d-7e88639e58f6"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: AWS_ACCOUNT_ID is not set."
  echo "Set it in your .env file or export it: export AWS_ACCOUNT_ID=123456789012"
  exit 1
fi

ORIGIN_DOMAIN="${FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
ORIGIN_ID="s3-static-website"

echo "=== Setting up CloudFront (profile: $AWS_PROFILE, region: $AWS_REGION) ==="

# ---- Step 1: Check for existing distribution ----
echo ""
echo "--- Checking for existing distribution ---"
EXISTING_DIST_ID=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='${DISTRIBUTION_COMMENT}'].Id | [0]" \
  --output text 2>/dev/null || true)

if [[ -n "$EXISTING_DIST_ID" && "$EXISTING_DIST_ID" != "None" ]]; then
  echo "Distribution already exists (ID: $EXISTING_DIST_ID)."
  DIST_DOMAIN=$(aws cloudfront get-distribution \
    --id "$EXISTING_DIST_ID" \
    --profile "$AWS_PROFILE" \
    --query 'Distribution.DomainName' --output text)
  echo "Domain: $DIST_DOMAIN"
  DIST_ID="$EXISTING_DIST_ID"
else
  # ---- Step 2: Create CloudFront distribution ----
  echo "Creating CloudFront distribution..."
  echo "Origin: $ORIGIN_DOMAIN (HTTP only)"

  CALLER_REF="twin-$(date +%s)"

  DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "${CALLER_REF}",
  "Comment": "${DISTRIBUTION_COMMENT}",
  "DefaultRootObject": "index.html",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http2",
  "IsIPV6Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "${ORIGIN_ID}",
        "DomainName": "${ORIGIN_DOMAIN}",
        "OriginPath": "",
        "CustomHeaders": { "Quantity": 0 },
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          },
          "OriginReadTimeout": 30,
          "OriginKeepaliveTimeout": 5
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "${ORIGIN_ID}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["HEAD", "GET"]
      }
    },
    "Compress": true,
    "CachePolicyId": "${CACHING_OPTIMIZED_POLICY_ID}"
  },
  "CacheBehaviors": { "Quantity": 0 },
  "CustomErrorResponses": { "Quantity": 0 },
  "Restrictions": {
    "GeoRestriction": {
      "RestrictionType": "none",
      "Quantity": 0
    }
  },
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true,
    "MinimumProtocolVersion": "TLSv1.2_2021",
    "CertificateSource": "cloudfront"
  },
  "WebACLId": "",
  "Logging": {
    "Enabled": false,
    "IncludeCookies": false,
    "Bucket": "",
    "Prefix": ""
  }
}
EOF
  )

  DIST_RESULT=$(aws cloudfront create-distribution \
    --distribution-config "$DIST_CONFIG" \
    --profile "$AWS_PROFILE" \
    --output json)

  DIST_ID=$(echo "$DIST_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['Id'])")
  DIST_DOMAIN=$(echo "$DIST_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['DomainName'])")

  echo "Distribution created!"
  echo "  ID:     $DIST_ID"
  echo "  Domain: $DIST_DOMAIN"
fi

# ---- Step 3: Update Lambda CORS_ORIGINS to CloudFront domain ----
echo ""
echo "--- Updating Lambda CORS_ORIGINS ---"
CLOUDFRONT_URL="https://${DIST_DOMAIN}"

# Get current environment variables
CURRENT_ENV=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'Environment.Variables' \
  --output json 2>/dev/null || echo "{}")

# Update CORS_ORIGINS — no trailing slash
UPDATED_ENV=$(echo "$CURRENT_ENV" | python3 -c "
import sys, json
env = json.load(sys.stdin)
env['CORS_ORIGINS'] = '${CLOUDFRONT_URL}'
print(json.dumps({'Variables': env}))
")

aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --environment "$UPDATED_ENV" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'FunctionName' --output text > /dev/null

echo "CORS_ORIGINS set to '${CLOUDFRONT_URL}'"
echo "  (starts with https://, no trailing slash)"

# ---- Step 4: Create initial cache invalidation ----
echo ""
echo "--- Creating cache invalidation ---"
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths '/*' \
  --profile "$AWS_PROFILE" \
  --query 'Invalidation.Id' --output text > /dev/null
echo "Invalidation created for /*"

# ---- Summary ----
echo ""
echo "=== CloudFront Setup Complete ==="
echo ""
echo "Distribution ID: $DIST_ID"
echo "Domain:          $DIST_DOMAIN"
echo "URL:             ${CLOUDFRONT_URL}"
echo ""
echo "Origin:          $ORIGIN_DOMAIN (HTTP only)"
echo "Cache Policy:    CachingOptimized"
echo "Viewer Policy:   Redirect HTTP to HTTPS"
echo "Price Class:     PriceClass_100 (North America & Europe)"
echo ""
echo "Lambda CORS_ORIGINS updated to: ${CLOUDFRONT_URL}"
echo ""
echo "NOTE: CloudFront takes 5-15 minutes to deploy globally."
echo "Check status with:"
echo "  aws cloudfront get-distribution --id $DIST_ID --profile $AWS_PROFILE --query 'Distribution.Status'"
