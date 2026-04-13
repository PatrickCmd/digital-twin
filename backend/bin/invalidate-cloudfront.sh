#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
DISTRIBUTION_COMMENT="twin-distribution"
PATHS="${1:-/*}"

echo "=== CloudFront Cache Invalidation ==="
echo ""

# Find distribution by comment
DIST_ID=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='${DISTRIBUTION_COMMENT}'].Id | [0]" \
  --output text 2>/dev/null || true)

if [[ -z "$DIST_ID" || "$DIST_ID" == "None" ]]; then
  echo "ERROR: Distribution '$DISTRIBUTION_COMMENT' not found. Run setup-cloudfront.sh first."
  exit 1
fi

echo "Distribution: $DIST_ID"
echo "Paths:        $PATHS"
echo ""

INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "$PATHS" \
  --profile "$AWS_PROFILE" \
  --query 'Invalidation.Id' --output text)

echo "Invalidation created: $INVALIDATION_ID"
echo ""
echo "Check status with:"
echo "  aws cloudfront get-invalidation --distribution-id $DIST_ID --id $INVALIDATION_ID --profile $AWS_PROFILE"
