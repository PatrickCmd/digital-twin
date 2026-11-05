#!/bin/bash
# Shared helpers for the one-time bootstrap scripts (state backend, GitHub OIDC).
#
# These resources live OUTSIDE the per-environment S3 state that deploy.sh uses,
# so the bootstrap scripts run Terraform with their own local state file
# (terraform/bootstrap.tfstate, gitignored) and their own plugin directory
# (terraform/.terraform-bootstrap). A backend override file switches the S3
# backend declared in backend.tf to "local" for the duration of the script.
#
# Usage (from a script in scripts/):
#   source "$(dirname "$0")/bootstrap-common.sh"
#   bootstrap_begin            # cd terraform/, write override, init
#   import_if_missing <addr> <id>
#   ...terraform apply -target=... "${TF_VARS[@]}"
#   (bootstrap_end runs automatically on exit)

set -e

AWS_PROFILE_NAME="${AWS_PROFILE:-patrickcmd}"
export AWS_PROFILE="${AWS_PROFILE_NAME}"
export AWS_DEFAULT_REGION="${DEFAULT_AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_REGION="${AWS_DEFAULT_REGION}"
export TF_IN_AUTOMATION=1
export TF_INPUT=0
export TF_DATA_DIR=".terraform-bootstrap"
export TF_VAR_aws_profile="${AWS_PROFILE_NAME}"

# The root module requires these; the bootstrap resources do not use them.
TF_VARS=(-var="project_name=${PROJECT_NAME:-twin}" -var="environment=${ENVIRONMENT:-dev}")

OVERRIDE_FILE="backend_override.tf"

bootstrap_begin() {
    echo "Using AWS profile: ${AWS_PROFILE_NAME} (region ${AWS_DEFAULT_REGION})"
    cd "$(dirname "${BASH_SOURCE[1]}")/../terraform"
    cat > "${OVERRIDE_FILE}" <<'TF'
# Written by scripts/bootstrap-common.sh for the duration of a bootstrap script.
# Overrides the S3 backend in backend.tf with local state for bootstrap resources.
terraform {
  backend "local" {
    path = "bootstrap.tfstate"
  }
}
TF
    trap bootstrap_end EXIT
    adopt_legacy_local_state
    echo "Initializing Terraform (local bootstrap state: terraform/bootstrap.tfstate)..."
    terraform init -input=false -reconfigure >/dev/null
    terraform workspace select default >/dev/null 2>&1 || true
}

bootstrap_end() {
    rm -f "${OVERRIDE_FILE}"
}

# The original bootstrap runs used Terraform's default local state
# (terraform/terraform.tfstate). If it is still there, Terraform would stop
# and ask to migrate it. Adopt it as bootstrap.tfstate instead (it holds the
# OIDC provider, roles and state bucket), keeping a copy, and move any local
# workspace directory aside so nothing is left for Terraform to migrate.
adopt_legacy_local_state() {
    local stamp
    stamp=$(date +%Y%m%d%H%M%S)
    if [ -s terraform.tfstate ]; then
        if [ ! -s bootstrap.tfstate ]; then
            echo "Adopting existing local state terraform.tfstate as bootstrap.tfstate"
            cp terraform.tfstate "terraform.tfstate.pre-bootstrap-${stamp}"
            mv terraform.tfstate bootstrap.tfstate
        else
            echo "Moving stale terraform.tfstate aside (bootstrap.tfstate already exists)"
            mv terraform.tfstate "terraform.tfstate.pre-bootstrap-${stamp}"
        fi
        echo "  (copy kept as terraform.tfstate.pre-bootstrap-${stamp}; gitignored)"
    fi
    if [ -d terraform.tfstate.d ]; then
        echo "Moving local workspace states terraform.tfstate.d aside"
        mv terraform.tfstate.d "terraform.tfstate.d.pre-bootstrap-${stamp}"
    fi
}

# import_if_missing <resource address> <import id> [extra -var args...]
# Imports an existing AWS resource into the bootstrap state so re-running a
# bootstrap script updates it instead of failing with "already exists".
import_if_missing() {
    local addr="$1" id="$2"; shift 2
    if terraform state list 2>/dev/null | grep -qx "${addr}"; then
        return 0
    fi
    if terraform import "${TF_VARS[@]}" "$@" "${addr}" "${id}" >/dev/null 2>&1; then
        echo "  imported ${addr}"
    else
        echo "  ${addr} not found in AWS; it will be created"
    fi
}
