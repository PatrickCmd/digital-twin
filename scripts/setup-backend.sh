#!/bin/bash
# One-time: create the S3 bucket + DynamoDB table that hold Terraform state.
# Safe to re-run: existing resources are imported into the local bootstrap state.
# Uses the admin AWS profile (default: patrickcmd; override with AWS_PROFILE=<name>).
set -e
source "$(dirname "$0")/bootstrap-common.sh"

echo "🔧 Setting up Terraform state management resources..."
bootstrap_begin

if [ ! -f "backend-setup.tf" ]; then
    if [ -f "backend-setup.tf.backup" ]; then
        echo "📦 Restoring backend-setup.tf from backup..."
        cp backend-setup.tf.backup backend-setup.tf
    else
        echo "❌ Error: backend-setup.tf not found (and no backup exists)"
        exit 1
    fi
fi
# Re-init so the restored file is part of the configuration.
terraform init -input=false -reconfigure >/dev/null

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="twin-terraform-state-${AWS_ACCOUNT_ID}"

echo "🔎 Importing existing resources (if any)..."
import_if_missing aws_s3_bucket.terraform_state "${STATE_BUCKET}"
import_if_missing aws_s3_bucket_versioning.terraform_state "${STATE_BUCKET}"
import_if_missing aws_s3_bucket_server_side_encryption_configuration.terraform_state "${STATE_BUCKET}"
import_if_missing aws_s3_bucket_public_access_block.terraform_state "${STATE_BUCKET}"
import_if_missing aws_dynamodb_table.terraform_locks "twin-terraform-locks"

echo "🚀 Applying state management resources..."
terraform apply "${TF_VARS[@]}" \
  -target=aws_s3_bucket.terraform_state \
  -target=aws_s3_bucket_versioning.terraform_state \
  -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
  -target=aws_s3_bucket_public_access_block.terraform_state \
  -target=aws_dynamodb_table.terraform_locks

echo ""
echo "📋 Verifying outputs..."
echo "State bucket: $(terraform output -raw state_bucket_name)"
echo "DynamoDB table: $(terraform output -raw dynamodb_table_name)"

echo ""
echo "📦 Backing up backend-setup.tf to backend-setup.tf.backup..."
mv backend-setup.tf backend-setup.tf.backup

echo ""
echo "✅ State management resources ready."
echo "💡 Bootstrap state is in terraform/bootstrap.tfstate (gitignored); keep it with your other local secrets."
