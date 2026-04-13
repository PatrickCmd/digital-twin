#!/bin/bash
set -e

echo "🔧 Setting up Terraform state management resources..."

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

# Ensure backend-setup.tf exists
if [ ! -f "backend-setup.tf" ]; then
    # Check for backup
    if [ -f "backend-setup.tf.backup" ]; then
        echo "📦 Restoring backend-setup.tf from backup..."
        cp backend-setup.tf.backup backend-setup.tf
    else
        echo "❌ Error: backend-setup.tf not found (and no backup exists)"
        exit 1
    fi
fi

# Make sure we're in the default workspace
echo "📂 Selecting default workspace..."
terraform workspace select default 2>/dev/null || true

# Initialize Terraform
echo "🔄 Initializing Terraform..."
terraform init -input=false

# Apply just the backend resources (targeted apply)
echo "🚀 Applying state management resources..."
terraform apply \
  -target=aws_s3_bucket.terraform_state \
  -target=aws_s3_bucket_versioning.terraform_state \
  -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
  -target=aws_s3_bucket_public_access_block.terraform_state \
  -target=aws_dynamodb_table.terraform_locks

# Verify the resources were created
echo ""
echo "📋 Verifying outputs..."
echo "State bucket: $(terraform output -raw state_bucket_name)"
echo "DynamoDB table: $(terraform output -raw dynamodb_table_name)"

# Backup the setup file instead of removing it
echo ""
echo "📦 Backing up backend-setup.tf to backend-setup.tf.backup..."
mv backend-setup.tf backend-setup.tf.backup

echo ""
echo "✅ State management resources created successfully!"
echo "💡 The backend-setup.tf has been backed up to backend-setup.tf.backup"
