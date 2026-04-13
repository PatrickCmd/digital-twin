#!/bin/bash
set -e

ROLE_NAME="github-actions-twin-deploy"
DYNAMODB_TABLE="twin-terraform-locks"

echo "=== GitHub Actions CI/CD Resource Cleanup ==="
echo ""
echo "This will remove:"
echo "  - IAM Role: ${ROLE_NAME} (+ all attached policies)"
echo "  - S3 State Bucket: twin-terraform-state-<account_id>"
echo "  - DynamoDB Lock Table: ${DYNAMODB_TABLE}"
echo "  - OIDC Provider: token.actions.githubusercontent.com (if no other roles use it)"
echo ""

# Require confirmation
read -p "Are you sure? Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="twin-terraform-state-${AWS_ACCOUNT_ID}"

echo ""

# 1. Detach managed policies and delete inline policies from the IAM role
echo "--- Step 1: Cleaning up IAM Role ---"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "Detaching managed policies..."
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    for POLICY_ARN in $ATTACHED_POLICIES; do
        echo "  Detaching: $POLICY_ARN"
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
    done

    echo "Deleting inline policies..."
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text)
    for POLICY_NAME in $INLINE_POLICIES; do
        echo "  Deleting: $POLICY_NAME"
        aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME"
    done

    echo "Deleting IAM role: $ROLE_NAME"
    aws iam delete-role --role-name "$ROLE_NAME"
    echo "  Done."
else
    echo "  Role '$ROLE_NAME' not found, skipping."
fi

# 2. Empty and delete the S3 state bucket
echo ""
echo "--- Step 2: Removing S3 State Bucket ---"
if aws s3 ls "s3://$STATE_BUCKET" &>/dev/null; then
    echo "Emptying bucket: $STATE_BUCKET"
    aws s3 rm "s3://$STATE_BUCKET" --recursive

    # Also delete versioned objects
    echo "Deleting versioned objects..."
    VERSIONS=$(aws s3api list-object-versions --bucket "$STATE_BUCKET" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
    if [ "$VERSIONS" != '{"Objects": null}' ] && [ -n "$VERSIONS" ]; then
        echo "$VERSIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('Objects'):
    for obj in data['Objects']:
        print(f\"  Deleting version: {obj['Key']} ({obj['VersionId']})\")
" 2>/dev/null || true
        aws s3api delete-objects --bucket "$STATE_BUCKET" --delete "$VERSIONS" >/dev/null 2>&1 || true
    fi

    # Delete markers too
    DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$STATE_BUCKET" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
    if [ "$DELETE_MARKERS" != '{"Objects": null}' ] && [ -n "$DELETE_MARKERS" ]; then
        aws s3api delete-objects --bucket "$STATE_BUCKET" --delete "$DELETE_MARKERS" >/dev/null 2>&1 || true
    fi

    echo "Deleting bucket: $STATE_BUCKET"
    aws s3 rb "s3://$STATE_BUCKET"
    echo "  Done."
else
    echo "  Bucket '$STATE_BUCKET' not found, skipping."
fi

# 3. Delete the DynamoDB lock table
echo ""
echo "--- Step 3: Removing DynamoDB Lock Table ---"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" &>/dev/null; then
    echo "Deleting table: $DYNAMODB_TABLE"
    aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" >/dev/null
    echo "  Done."
else
    echo "  Table '$DYNAMODB_TABLE' not found, skipping."
fi

# 4. Optionally remove the OIDC provider
echo ""
echo "--- Step 4: OIDC Provider ---"
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
    read -p "Delete OIDC provider? Only do this if no other roles use it (yes/no): " OIDC_CONFIRM
    if [ "$OIDC_CONFIRM" = "yes" ]; then
        echo "Deleting OIDC provider..."
        aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN"
        echo "  Done."
    else
        echo "  Skipped OIDC provider deletion."
    fi
else
    echo "  OIDC provider not found, skipping."
fi

# 5. Remove GitHub repository secrets
echo ""
echo "--- Step 5: GitHub Repository Secrets ---"
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    read -p "Remove GitHub secrets (AWS_ROLE_ARN, DEFAULT_AWS_REGION, AWS_ACCOUNT_ID)? (yes/no): " SECRETS_CONFIRM
    if [ "$SECRETS_CONFIRM" = "yes" ]; then
        for SECRET in AWS_ROLE_ARN DEFAULT_AWS_REGION AWS_ACCOUNT_ID; do
            echo "  Removing: $SECRET"
            gh secret delete "$SECRET" 2>/dev/null || echo "    Not found, skipping."
        done
        echo "  Done."
    else
        echo "  Skipped secrets removal."
    fi
else
    echo "  GitHub CLI not available or not authenticated, skipping."
fi

echo ""
echo "=== Cleanup complete! ==="
echo ""
echo "Resources removed:"
echo "  - IAM Role and policies"
echo "  - S3 state bucket (with all versions)"
echo "  - DynamoDB lock table"
echo ""
echo "Note: GitHub Actions workflows (.github/workflows/) are still in the repo."
echo "Remove them manually if no longer needed."
