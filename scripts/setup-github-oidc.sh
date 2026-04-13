#!/bin/bash
set -e

GITHUB_REPO=${1:-"PatrickCmd/digital-twin"}

echo "Setting up GitHub Actions OIDC for repo: ${GITHUB_REPO}"

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

# Ensure github-oidc.tf exists
if [ ! -f "github-oidc.tf" ]; then
    if [ -f "github-oidc.tf.backup" ]; then
        echo "Restoring github-oidc.tf from backup..."
        cp github-oidc.tf.backup github-oidc.tf
    else
        echo "Error: github-oidc.tf not found (and no backup exists)"
        exit 1
    fi
fi

# Make sure we're in the default workspace
echo "Selecting default workspace..."
terraform workspace select default 2>/dev/null || true

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -input=false

# Check if the OIDC provider already exists in the AWS account
echo "Checking if GitHub OIDC provider already exists..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_EXISTS=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, 'oidc-provider/token.actions.githubusercontent.com')]" --output text)

if [ -n "$OIDC_EXISTS" ]; then
    echo "GitHub OIDC provider already exists in your account."
    echo "Importing into Terraform state..."
    terraform import -var="github_repository=${GITHUB_REPO}" \
        aws_iam_openid_connect_provider.github \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" 2>/dev/null || true
    echo ""
    echo "Applying IAM role and policies (OIDC provider already imported)..."
    terraform apply \
        -target=aws_iam_role.github_actions \
        -target=aws_iam_role_policy_attachment.github_lambda \
        -target=aws_iam_role_policy_attachment.github_s3 \
        -target=aws_iam_role_policy_attachment.github_apigateway \
        -target=aws_iam_role_policy_attachment.github_cloudfront \
        -target=aws_iam_role_policy_attachment.github_iam_read \
        -target=aws_iam_role_policy_attachment.github_bedrock \
        -target=aws_iam_role_policy_attachment.github_dynamodb \
        -target=aws_iam_role_policy_attachment.github_acm \
        -target=aws_iam_role_policy_attachment.github_route53 \
        -target=aws_iam_role_policy.github_additional \
        -var="github_repository=${GITHUB_REPO}"
else
    echo "GitHub OIDC provider does not exist. Creating all resources..."
    terraform apply \
        -target=aws_iam_openid_connect_provider.github \
        -target=aws_iam_role.github_actions \
        -target=aws_iam_role_policy_attachment.github_lambda \
        -target=aws_iam_role_policy_attachment.github_s3 \
        -target=aws_iam_role_policy_attachment.github_apigateway \
        -target=aws_iam_role_policy_attachment.github_cloudfront \
        -target=aws_iam_role_policy_attachment.github_iam_read \
        -target=aws_iam_role_policy_attachment.github_bedrock \
        -target=aws_iam_role_policy_attachment.github_dynamodb \
        -target=aws_iam_role_policy_attachment.github_acm \
        -target=aws_iam_role_policy_attachment.github_route53 \
        -target=aws_iam_role_policy.github_additional \
        -var="github_repository=${GITHUB_REPO}"
fi

# Print the role ARN
echo ""
echo "Verifying output..."
ROLE_ARN=$(terraform output -raw github_actions_role_arn)
echo "GitHub Actions Role ARN: ${ROLE_ARN}"

# Backup the setup file
echo ""
echo "Backing up github-oidc.tf to github-oidc.tf.backup..."
mv github-oidc.tf github-oidc.tf.backup

echo ""
echo "Setup complete!"
echo ""
echo "Save this Role ARN for GitHub Secrets:"
echo "  AWS_ROLE_ARN=${ROLE_ARN}"
echo ""
echo "Next steps:"
echo "  1. Go to your GitHub repo: Settings > Secrets and variables > Actions"
echo "  2. Add these repository secrets:"
echo "     - AWS_ROLE_ARN = ${ROLE_ARN}"
echo "     - DEFAULT_AWS_REGION = us-east-1"
echo "     - AWS_ACCOUNT_ID = ${AWS_ACCOUNT_ID}"
