terraform {
  backend "s3" {
    # These values will be set by deployment scripts via -backend-config flags
    # For local development, pass them manually:
    #   terraform init \
    #     -backend-config="bucket=twin-terraform-state-<ACCOUNT_ID>" \
    #     -backend-config="key=<ENVIRONMENT>/terraform.tfstate" \
    #     -backend-config="region=us-east-1" \
    #     -backend-config="dynamodb_table=twin-terraform-locks" \
    #     -backend-config="encrypt=true"
  }
}
