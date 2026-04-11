#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="aiengineer"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"
FUNCTION_NAME="twin-api"
OUTFILE=$(mktemp /tmp/lambda-response.XXXXXX.json)
trap 'rm -f "$OUTFILE"' EXIT

PAYLOAD='{
  "version": "2.0",
  "routeKey": "GET /health",
  "rawPath": "/health",
  "headers": {
    "accept": "application/json",
    "content-type": "application/json",
    "user-agent": "test-invoke"
  },
  "requestContext": {
    "http": {
      "method": "GET",
      "path": "/health",
      "protocol": "HTTP/1.1",
      "sourceIp": "127.0.0.1",
      "userAgent": "test-invoke"
    },
    "routeKey": "GET /health",
    "stage": "$default"
  },
  "isBase64Encoded": false
}'

echo "=== Testing Lambda Function: $FUNCTION_NAME (profile: $AWS_PROFILE, region: $AWS_REGION) ==="
echo ""

# Invoke Lambda — payload goes to OUTFILE, metadata to stdout
echo "Invoking $FUNCTION_NAME..."
METADATA=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  "$OUTFILE")

echo "--- Invoke Metadata ---"
echo "$METADATA"
echo ""

# Check for function error
if echo "$METADATA" | grep -q '"FunctionError"'; then
  echo "ERROR: Lambda function returned an error."
  echo ""
  echo "--- Error Response ---"
  cat "$OUTFILE"
  exit 1
fi

echo "--- Lambda Response ---"
python3 -m json.tool "$OUTFILE" 2>/dev/null || cat "$OUTFILE"
echo ""

# Parse body from the API Gateway response
BODY=$(python3 -c "
import json
with open('$OUTFILE') as f:
    resp = json.load(f)
body = json.loads(resp.get('body', '{}'))
print(json.dumps(body, indent=2))
" 2>/dev/null || true)

if [[ -n "$BODY" ]]; then
  echo "--- Parsed Body ---"
  echo "$BODY"
  echo ""

  if echo "$BODY" | grep -q '"status"'; then
    echo "SUCCESS: Lambda health check passed!"
  else
    echo "WARNING: Unexpected response body."
  fi
else
  echo "Could not parse response body — check the raw response above."
fi
