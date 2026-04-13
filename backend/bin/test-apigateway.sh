#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
API_NAME="twin-api-gateway"

echo "=== Testing API Gateway: $API_NAME ==="
echo ""

# Find the API endpoint
API_ENDPOINT=$(aws apigatewayv2 get-apis \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiEndpoint | [0]" \
  --output text 2>/dev/null || true)

if [[ -z "$API_ENDPOINT" || "$API_ENDPOINT" == "None" ]]; then
  echo "ERROR: API '$API_NAME' not found. Run setup-apigateway.sh first."
  exit 1
fi

echo "API Endpoint: $API_ENDPOINT"
echo ""

# ---- Test 1: Health check (GET /health) ----
echo "--- Test 1: GET /health ---"
HTTP_CODE=$(curl -s -o /tmp/apigw-health.json -w "%{http_code}" "${API_ENDPOINT}/health")
BODY=$(cat /tmp/apigw-health.json)

echo "Status: $HTTP_CODE"
echo "Body:   $BODY"

if [[ "$HTTP_CODE" == "200" ]] && echo "$BODY" | grep -q '"status"'; then
  echo "PASS"
else
  echo "FAIL"
fi
echo ""

# ---- Test 2: Root endpoint (GET /) ----
echo "--- Test 2: GET / ---"
HTTP_CODE=$(curl -s -o /tmp/apigw-root.json -w "%{http_code}" "${API_ENDPOINT}/")
BODY=$(cat /tmp/apigw-root.json)

echo "Status: $HTTP_CODE"
echo "Body:   $BODY"

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
echo ""

# ---- Test 3: CORS preflight (OPTIONS /chat) ----
echo "--- Test 3: OPTIONS /chat (CORS preflight) ---"
CORS_RESPONSE=$(curl -s -D - -o /dev/null \
  -X OPTIONS \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "${API_ENDPOINT}/chat")

echo "$CORS_RESPONSE" | grep -i "access-control" || echo "(no CORS headers found)"

if echo "$CORS_RESPONSE" | grep -qi "access-control-allow-origin"; then
  echo "PASS"
else
  echo "FAIL (CORS headers missing)"
fi
echo ""

# ---- Test 4: Chat endpoint (POST /chat) ----
echo "--- Test 4: POST /chat ---"
HTTP_CODE=$(curl -s -o /tmp/apigw-chat.json -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, who are you?"}' \
  "${API_ENDPOINT}/chat")
BODY=$(cat /tmp/apigw-chat.json)

echo "Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "Body:"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  echo "PASS"
else
  echo "Body: $BODY"
  echo "FAIL"
fi
echo ""

# ---- Cleanup temp files ----
rm -f /tmp/apigw-health.json /tmp/apigw-root.json /tmp/apigw-chat.json

echo "=== API Gateway Tests Complete ==="
