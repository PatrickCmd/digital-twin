#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
INVALIDATION_PATH=${2:-"/*"}

echo "Invalidating CloudFront cache for ${ENVIRONMENT} (path: ${INVALIDATION_PATH})..."

cd "$(dirname "$0")/../terraform"
terraform init -input=false > /dev/null

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  echo "ERROR: Workspace '${ENVIRONMENT}' does not exist."
  echo "Available workspaces:"
  terraform workspace list
  exit 1
fi

terraform workspace select "$ENVIRONMENT"

DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || true)

if [ -z "$DISTRIBUTION_ID" ]; then
  echo "ERROR: Could not retrieve CloudFront distribution ID from Terraform output."
  exit 1
fi

echo "Distribution: ${DISTRIBUTION_ID}"

INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "$INVALIDATION_PATH" \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation created: ${INVALIDATION_ID}"
echo "Done."
