#!/bin/bash
set -e

AWS_REGION=${1:-us-east-1}

echo "Setting up GitHub Actions repository secrets..."

# Check gh CLI is installed and authenticated
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it: https://cli.github.com/"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated."
    echo "Run: gh auth login"
    exit 1
fi

# Auto-detect values
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-twin-deploy"

# Verify the role exists
if ! aws iam get-role --role-name github-actions-twin-deploy &> /dev/null; then
    echo "Error: IAM role 'github-actions-twin-deploy' not found."
    echo "Run ./scripts/setup-github-oidc.sh first."
    exit 1
fi

echo ""
echo "Secrets to set:"
echo "  AWS_ROLE_ARN       = ${AWS_ROLE_ARN}"
echo "  DEFAULT_AWS_REGION = ${AWS_REGION}"
echo "  AWS_ACCOUNT_ID     = ${AWS_ACCOUNT_ID}"
echo ""

# Set secrets
echo "Setting AWS_ROLE_ARN..."
gh secret set AWS_ROLE_ARN --body "${AWS_ROLE_ARN}"

echo "Setting DEFAULT_AWS_REGION..."
gh secret set DEFAULT_AWS_REGION --body "${AWS_REGION}"

echo "Setting AWS_ACCOUNT_ID..."
gh secret set AWS_ACCOUNT_ID --body "${AWS_ACCOUNT_ID}"

# Verify
echo ""
echo "Verifying secrets..."
gh secret list

echo ""
echo "GitHub Actions secrets configured successfully!"
