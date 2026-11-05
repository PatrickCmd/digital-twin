#!/bin/bash
# One-time: create the GitHub OIDC provider and the deploy + plan IAM roles.
# Safe to re-run: existing resources are imported into the local bootstrap state
# and updated in place (e.g. a tightened trust policy).
# Uses the admin AWS profile (default: patrickcmd; override with AWS_PROFILE=<name>).
set -e
source "$(dirname "$0")/bootstrap-common.sh"

GITHUB_REPO=${1:-"PatrickCmd/digital-twin"}
export TF_VAR_github_repository="${GITHUB_REPO}"

echo "Setting up GitHub Actions OIDC for repo: ${GITHUB_REPO}"
bootstrap_begin

if [ ! -f "github-oidc.tf" ]; then
    if [ -f "github-oidc.tf.backup" ]; then
        echo "Restoring github-oidc.tf from backup..."
        cp github-oidc.tf.backup github-oidc.tf
    else
        echo "Error: github-oidc.tf not found (and no backup exists)"
        exit 1
    fi
fi
# Re-init so the restored file is part of the configuration.
terraform init -input=false -reconfigure >/dev/null

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DEPLOY_ROLE="github-actions-twin-deploy"
PLAN_ROLE="github-actions-twin-plan"

echo "Importing existing resources (if any)..."
import_if_missing aws_iam_openid_connect_provider.github \
    "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
import_if_missing aws_iam_role.github_actions "${DEPLOY_ROLE}"
import_if_missing aws_iam_role_policy_attachment.github_lambda     "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AWSLambda_FullAccess"
import_if_missing aws_iam_role_policy_attachment.github_s3         "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AmazonS3FullAccess"
import_if_missing aws_iam_role_policy_attachment.github_apigateway "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
import_if_missing aws_iam_role_policy_attachment.github_cloudfront "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/CloudFrontFullAccess"
import_if_missing aws_iam_role_policy_attachment.github_iam_read   "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/IAMReadOnlyAccess"
import_if_missing aws_iam_role_policy_attachment.github_bedrock    "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
import_if_missing aws_iam_role_policy_attachment.github_dynamodb   "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
import_if_missing aws_iam_role_policy_attachment.github_acm        "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess"
import_if_missing aws_iam_role_policy_attachment.github_route53    "${DEPLOY_ROLE}/arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
import_if_missing aws_iam_role_policy.github_additional            "${DEPLOY_ROLE}:github-actions-additional"
import_if_missing aws_iam_role.github_actions_plan "${PLAN_ROLE}"
import_if_missing aws_iam_role_policy_attachment.github_plan_readonly "${PLAN_ROLE}/arn:aws:iam::aws:policy/ReadOnlyAccess"
import_if_missing aws_iam_role_policy.github_plan_state               "${PLAN_ROLE}:github-actions-plan-state"

echo ""
echo "Applying OIDC provider, deploy role and plan role..."
terraform apply "${TF_VARS[@]}" \
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
    -target=aws_iam_role.github_actions_plan \
    -target=aws_iam_role_policy_attachment.github_plan_readonly \
    -target=aws_iam_role_policy.github_plan_state

echo ""
echo "Verifying output..."
ROLE_ARN=$(terraform output -raw github_actions_role_arn)
PLAN_ROLE_ARN=$(terraform output -raw github_actions_plan_role_arn)
echo "GitHub Actions Deploy Role ARN: ${ROLE_ARN}"
echo "GitHub Actions Plan Role ARN:   ${PLAN_ROLE_ARN}"

echo ""
echo "Backing up github-oidc.tf to github-oidc.tf.backup..."
mv github-oidc.tf github-oidc.tf.backup

echo ""
echo "Setup complete!"
echo ""
echo "Save these Role ARNs for GitHub Secrets (or run ./scripts/setup-github-secrets.sh):"
echo "  AWS_ROLE_ARN=${ROLE_ARN}"
echo "  AWS_PLAN_ROLE_ARN=${PLAN_ROLE_ARN}"
echo ""
echo "Next steps:"
echo "  1. ./scripts/setup-github-secrets.sh"
echo "  2. GitHub: Settings > Environments > prod > add yourself as a required reviewer"
echo "💡 Bootstrap state is in terraform/bootstrap.tfstate (gitignored)."
