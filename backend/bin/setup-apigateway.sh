#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
FUNCTION_NAME="twin-api"
API_NAME="twin-api-gateway"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: AWS_ACCOUNT_ID is not set."
  echo "Set it in your .env file or export it: export AWS_ACCOUNT_ID=123456789012"
  exit 1
fi

LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}"

echo "=== Setting up API Gateway (profile: $AWS_PROFILE, region: $AWS_REGION) ==="

# ---- Step 1: Check if API already exists ----
echo ""
echo "--- Checking for existing API: $API_NAME ---"
EXISTING_API_ID=$(aws apigatewayv2 get-apis \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text 2>/dev/null || true)

if [[ -n "$EXISTING_API_ID" && "$EXISTING_API_ID" != "None" ]]; then
  echo "API '$API_NAME' already exists (ID: $EXISTING_API_ID)."
  API_ID="$EXISTING_API_ID"
else
  # ---- Step 2: Create HTTP API ----
  echo "Creating HTTP API: $API_NAME"
  API_ID=$(aws apigatewayv2 create-api \
    --name "$API_NAME" \
    --protocol-type HTTP \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'ApiId' --output text)
  echo "API created (ID: $API_ID)."
fi

API_ENDPOINT=$(aws apigatewayv2 get-api \
  --api-id "$API_ID" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'ApiEndpoint' --output text)

# ---- Step 3: Create Lambda integration ----
echo ""
echo "--- Creating Lambda integration ---"
# Check for existing integration
EXISTING_INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
  --api-id "$API_ID" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Items[?IntegrationUri=='${LAMBDA_ARN}'].IntegrationId | [0]" \
  --output text 2>/dev/null || true)

if [[ -n "$EXISTING_INTEGRATION_ID" && "$EXISTING_INTEGRATION_ID" != "None" ]]; then
  echo "Integration already exists (ID: $EXISTING_INTEGRATION_ID)."
  INTEGRATION_ID="$EXISTING_INTEGRATION_ID"
else
  INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$LAMBDA_ARN" \
    --payload-format-version "2.0" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'IntegrationId' --output text)
  echo "Integration created (ID: $INTEGRATION_ID)."
fi

INTEGRATION_TARGET="integrations/$INTEGRATION_ID"

# ---- Step 4: Create routes ----
echo ""
echo "--- Creating routes ---"

create_route() {
  local route_key="$1"

  # Check if route already exists
  local existing
  existing=$(aws apigatewayv2 get-routes \
    --api-id "$API_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "Items[?RouteKey=='${route_key}'].RouteId | [0]" \
    --output text 2>/dev/null || true)

  if [[ -n "$existing" && "$existing" != "None" ]]; then
    echo "  Route '$route_key' already exists, skipping."
    return
  fi

  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "$route_key" \
    --target "$INTEGRATION_TARGET" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'RouteId' --output text > /dev/null

  echo "  Route '$route_key' created."
}

create_route 'GET /'
create_route 'GET /health'
create_route 'POST /chat'
create_route 'OPTIONS /{proxy+}'
create_route 'ANY /{proxy+}'

# ---- Step 5: Create $default stage with auto-deploy ----
echo ""
echo "--- Configuring \$default stage with auto-deploy ---"
EXISTING_STAGE=$(aws apigatewayv2 get-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" 2>/dev/null || true)

if [[ -n "$EXISTING_STAGE" ]]; then
  aws apigatewayv2 update-stage \
    --api-id "$API_ID" \
    --stage-name '$default' \
    --auto-deploy \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'StageName' --output text > /dev/null
  echo "Stage '\$default' updated with auto-deploy."
else
  aws apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name '$default' \
    --auto-deploy \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'StageName' --output text > /dev/null
  echo "Stage '\$default' created with auto-deploy."
fi

# ---- Step 6: Configure CORS ----
echo ""
echo "--- Configuring CORS ---"
aws apigatewayv2 update-api \
  --api-id "$API_ID" \
  --cors-configuration \
    'AllowOrigins=*,AllowHeaders=*,AllowMethods=*,MaxAge=300' \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'CorsConfiguration' --output json
echo "CORS configured."

# ---- Step 7: Grant API Gateway permission to invoke Lambda ----
echo ""
echo "--- Granting API Gateway permission to invoke Lambda ---"
STATEMENT_ID="apigateway-invoke-${API_ID}"

# Check if permission already exists (remove and re-add to be safe)
aws lambda remove-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "$STATEMENT_ID" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" 2>/dev/null || true

aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "$STATEMENT_ID" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'Statement' --output text > /dev/null
echo "Lambda invoke permission granted."

# ---- Summary ----
echo ""
echo "=== API Gateway Setup Complete ==="
echo ""
echo "API Name:     $API_NAME"
echo "API ID:       $API_ID"
echo "Invoke URL:   $API_ENDPOINT"
echo ""
echo "Routes:"
echo "  GET  /          → $FUNCTION_NAME"
echo "  GET  /health    → $FUNCTION_NAME"
echo "  POST /chat      → $FUNCTION_NAME"
echo "  OPTIONS /{proxy+} → $FUNCTION_NAME"
echo "  ANY  /{proxy+}  → $FUNCTION_NAME"
echo ""
echo "Test it:"
echo "  curl ${API_ENDPOINT}/health"
