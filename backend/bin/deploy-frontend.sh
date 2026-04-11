#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FRONTEND_BUCKET="twin-frontend-${AWS_ACCOUNT_ID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/frontend"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: AWS_ACCOUNT_ID is not set."
  echo "Set it in your .env file or export it: export AWS_ACCOUNT_ID=123456789012"
  exit 1
fi

if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo "ERROR: Frontend directory not found at $FRONTEND_DIR"
  exit 1
fi

echo "=== Deploying Frontend (profile: $AWS_PROFILE, region: $AWS_REGION) ==="

# ---- Step 1: Install dependencies ----
echo ""
echo "--- Installing dependencies ---"
(cd "$FRONTEND_DIR" && npm install)

# ---- Step 2: Build static export ----
echo ""
echo "--- Building static export ---"
(cd "$FRONTEND_DIR" && npm run build)

OUT_DIR="$FRONTEND_DIR/out"
if [[ ! -d "$OUT_DIR" ]]; then
  echo "ERROR: Build did not produce an 'out' directory."
  echo "Ensure next.config.ts has output: 'export' set."
  exit 1
fi

FILE_COUNT=$(find "$OUT_DIR" -type f | wc -l | tr -d ' ')
echo "Build complete: $FILE_COUNT files in out/"

# ---- Step 3: Sync to S3 ----
echo ""
echo "--- Syncing to s3://$FRONTEND_BUCKET/ ---"
aws s3 sync "$OUT_DIR/" "s3://$FRONTEND_BUCKET/" \
  --delete \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"

echo "Upload complete."

# ---- Summary ----
WEBSITE_URL="http://${FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"

echo ""
echo "=== Frontend Deployment Complete ==="
echo ""
echo "Bucket:      $FRONTEND_BUCKET"
echo "Website URL: $WEBSITE_URL"
echo ""
echo "If using CloudFront, remember to create an invalidation:"
echo "  aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths '/*' --profile $AWS_PROFILE"
