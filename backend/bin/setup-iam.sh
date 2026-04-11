#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="patrickcmd"
GROUP_NAME="TwinAccess"
USER_NAME="aiengineer"

POLICIES=(
  "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
  "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
  "arn:aws:iam::aws:policy/CloudFrontFullAccess"
  "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
  "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess_v2"
)

echo "=== Setting up IAM for Digital Twin (profile: $AWS_PROFILE) ==="

# Step 1: Create IAM group
echo ""
echo "--- Creating IAM group: $GROUP_NAME ---"
if aws iam get-group --group-name "$GROUP_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
  echo "Group '$GROUP_NAME' already exists, skipping creation."
else
  aws iam create-group --group-name "$GROUP_NAME" --profile "$AWS_PROFILE"
  echo "Group '$GROUP_NAME' created."
fi

# Step 2: Attach policies to group
echo ""
echo "--- Attaching policies to $GROUP_NAME ---"
for policy_arn in "${POLICIES[@]}"; do
  policy_name=$(basename "$policy_arn")
  echo "  Attaching: $policy_name"
  aws iam attach-group-policy \
    --group-name "$GROUP_NAME" \
    --policy-arn "$policy_arn" \
    --profile "$AWS_PROFILE"
done
echo "All policies attached."

# Step 3: Add user to group
echo ""
echo "--- Adding user '$USER_NAME' to group '$GROUP_NAME' ---"
aws iam add-user-to-group \
  --group-name "$GROUP_NAME" \
  --user-name "$USER_NAME" \
  --profile "$AWS_PROFILE"
echo "User '$USER_NAME' added to group '$GROUP_NAME'."

# Summary
echo ""
echo "=== Setup complete ==="
echo "Group:    $GROUP_NAME"
echo "User:     $USER_NAME"
echo "Policies: ${#POLICIES[@]} attached"
echo ""
echo "You can now use the '$USER_NAME' IAM user for the Digital Twin project."
