# Digital Twin - Terraform Infrastructure

Infrastructure as Code for the Digital Twin project using Terraform with modular design.

## Architecture

```
CloudFront (HTTPS) → S3 (static frontend)
                         ↓ API calls
                   API Gateway → Lambda (FastAPI)
                                   ├── AWS Bedrock (AI responses)
                                   └── S3 (conversation memory)
```

## Module Structure

```
terraform/
├── versions.tf          # AWS provider config (profile: aiengineer)
├── variables.tf         # Root variables
├── main.tf              # Module orchestration
├── outputs.tf           # Root outputs
└── modules/
    ├── s3/              # Memory + frontend buckets
    ├── lambda/          # IAM role + Lambda function
    ├── api_gateway/     # HTTP API + routes
    ├── cloudfront/      # CDN distribution
    └── dns/             # Route53 + ACM (optional)
```

### Modules

| Module | Resources | Purpose |
|--------|-----------|---------|
| **s3** | 2 buckets, public access blocks, website config, bucket policy | Private memory storage + public frontend hosting |
| **lambda** | IAM role, 3 policy attachments, Lambda function | FastAPI app with Bedrock, S3, and CloudWatch access |
| **api_gateway** | HTTP API, stage, integration, 3 routes, Lambda permission | Routes HTTP requests to Lambda |
| **cloudfront** | Distribution with custom origin | HTTPS CDN for frontend, redirect HTTP to HTTPS |
| **dns** | Route53 record lookup, ACM cert lookup, A/AAAA subdomain aliases | Custom subdomain support using existing cert (optional, `use_custom_domain = true`) |

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with profile `aiengineer`
- Lambda deployment package built (`backend/lambda-deployment.zip`)
- Node.js 18+ (for frontend build)
- Python 3.12+ with [uv](https://docs.astral.sh/uv/) (for Lambda packaging)

## Deployment Scripts

Scripts are in the project root `scripts/` directory. Run from anywhere.

### Full Deploy

Builds Lambda package, applies Terraform, builds frontend, and syncs to S3.

```bash
./scripts/deploy.sh           # deploy to dev (default)
./scripts/deploy.sh test      # deploy to test
./scripts/deploy.sh prod      # deploy to prod (uses prod.tfvars)
```

The deploy script also runs `terraform fmt` and `terraform validate` before applying.

### CloudFront Invalidation

Invalidates cached content for a specific environment's CloudFront distribution.

```bash
./scripts/invalidate-cloudfront.sh             # invalidate dev, all paths
./scripts/invalidate-cloudfront.sh test        # invalidate test, all paths
./scripts/invalidate-cloudfront.sh prod /index.html  # specific path
```

### Destroy Environment

Empties S3 buckets and destroys all resources for a specific environment.

```bash
./scripts/destroy.sh dev       # destroy dev environment
./scripts/destroy.sh test      # destroy test environment
./scripts/destroy.sh prod      # destroy prod environment (uses prod.tfvars)
```

The environment argument is **required**. The script will:
1. Select the Terraform workspace for the environment
2. Empty the frontend and memory S3 buckets
3. Run `terraform destroy`

To also remove the workspace after destroying:
```bash
cd terraform
terraform workspace select default
terraform workspace delete dev
```

### Manual Terraform Usage

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project_name` | string | — | Name prefix for all resources (lowercase, hyphens only) |
| `environment` | string | — | `dev`, `test`, or `prod` |
| `bedrock_model_id` | string | `global.amazon.nova-2-lite-v1:0` | AWS Bedrock model ID |
| `lambda_timeout` | number | `60` | Lambda timeout in seconds |
| `api_throttle_burst_limit` | number | `10` | API Gateway burst limit |
| `api_throttle_rate_limit` | number | `5` | API Gateway rate limit |
| `use_custom_domain` | bool | `false` | Enable custom domain with Route53 + existing ACM cert |
| `root_domain` | string | `""` | Apex domain (e.g. `patrickcmd.dev`) |
| `subdomain_prefix` | string | `digital-twin` | Subdomain prefix. Environment prefix auto-added for dev/test |

## Outputs

| Output | Description |
|--------|-------------|
| `api_gateway_url` | API Gateway endpoint URL |
| `cloudfront_url` | CloudFront distribution URL |
| `s3_frontend_bucket` | Frontend bucket name |
| `s3_memory_bucket` | Memory bucket name |
| `lambda_function_name` | Lambda function name |
| `cloudfront_distribution_id` | CloudFront distribution ID (used by invalidation script) |
| `custom_domain_url` | Custom domain URL (if enabled) |

## Resource Naming

All resources use the pattern `{project_name}-{environment}-*` and are tagged with:

```hcl
Project     = var.project_name
Environment = var.environment
ManagedBy   = "terraform"
```

## Custom Domain

The DNS module uses an **existing** ACM certificate and Route53 hosted zone — it does not create new ones. It creates subdomain records pointing to the CloudFront distribution.

Subdomain pattern per environment:

| Environment | Subdomain |
|-------------|-----------|
| `prod` | `digital-twin.patrickcmd.dev` |
| `test` | `test-digital-twin.patrickcmd.dev` |
| `dev` | `dev-digital-twin.patrickcmd.dev` |

Production always uses the custom domain (`prod.tfvars` sets `use_custom_domain = true`).

### Enabling Custom Domain for Dev/Test

Create an environment-specific `.tfvars` file. The deploy and destroy scripts auto-detect `{environment}.tfvars` if it exists.

**Example** — `terraform/dev.tfvars`:
```hcl
project_name             = "twin"
environment              = "dev"
bedrock_model_id         = "global.amazon.nova-2-lite-v1:0"
use_custom_domain        = true
root_domain              = "patrickcmd.dev"
```

Then deploy normally:
```bash
./scripts/deploy.sh dev    # auto-detects dev.tfvars, creates dev-digital-twin.patrickcmd.dev
```

Without a `dev.tfvars`, the default `terraform.tfvars` is used (no custom domain — CloudFront URL only).

### Variable Files

| File | Environment | Custom Domain |
|------|-------------|---------------|
| `terraform.tfvars` | dev (default) | disabled |
| `dev.tfvars` | dev (optional) | enabled → `dev-digital-twin.patrickcmd.dev` |
| `test.tfvars` | test (optional) | enabled → `test-digital-twin.patrickcmd.dev` |
| `prod.tfvars` | prod | enabled → `digital-twin.patrickcmd.dev` |

## Workspaces

Terraform workspaces isolate state per environment. The deploy script manages these automatically.

```bash
terraform workspace list              # list all workspaces
terraform workspace select dev        # switch to dev
terraform workspace select prod       # switch to prod
```

## CI/CD with GitHub Actions

### How Remote State Works

By default, Terraform stores state **locally** in a `terraform.tfstate` file. This causes issues when multiple people or CI/CD pipelines run Terraform simultaneously (state corruption), when the state file lives on one machine (single point of failure), or when CI/CD runners are ephemeral (no persistent local state).

The solution is remote state in S3 with DynamoDB locking:

```
Developer A ─┐
              ├──→ S3 Bucket (terraform.tfstate) ──→ AWS Resources
Developer B ─┤         ↕
              │    DynamoDB (lock table)
CI/CD ───────┘
```

- **S3 Bucket** stores the state file remotely. Versioning keeps history for recovery, encryption (AES256) protects sensitive values, and public access is blocked.
- **DynamoDB Table** provides state locking. Before modifying state, Terraform writes a lock entry (keyed by `LockID`). If another process tries to run concurrently, it sees the lock and fails instead of corrupting state. The lock is released when Terraform finishes.

Once the resources exist, Terraform connects via a `backend` block. The `key` path is per-environment (`dev/`, `test/`, `prod/`), so each environment gets its own isolated state file within the same bucket.

The flow: `terraform init` connects to S3 and downloads current state. `terraform plan/apply` acquires a DynamoDB lock, reads state from S3, computes changes, writes updated state back, and releases the lock.

These resources are **infrastructure that manages infrastructure** — they must exist before Terraform can use them as a backend. That's why `backend-setup.tf` is a one-time bootstrap step that runs with local state, then gets backed up.

### State Management Resources

Remote state is stored in S3 with DynamoDB locking to enable CI/CD and team collaboration.

| Resource | Name | Purpose |
|----------|------|---------|
| **S3 Bucket** | `twin-terraform-state-<account_id>` | Versioned, encrypted (AES256) Terraform state storage |
| **DynamoDB Table** | `twin-terraform-locks` | State locking to prevent concurrent modifications |

#### Setup

Run the one-time setup script to create these resources:

```bash
./scripts/setup-backend.sh
```

The script applies targeted resources, verifies outputs, and backs up `backend-setup.tf` to `backend-setup.tf.backup`.

### GitHub Actions OIDC Authentication

GitHub Actions authenticates with AWS using OpenID Connect (OIDC) — no long-lived access keys needed. The flow:

```
GitHub Actions → requests OIDC JWT → AWS STS validates token → assumes IAM role → temporary credentials
```

| Resource | Name | Purpose |
|----------|------|---------|
| **OIDC Provider** | `token.actions.githubusercontent.com` | Trust relationship between GitHub and AWS |
| **IAM Role** | `github-actions-twin-deploy` | Role assumed by GitHub Actions workflows |
| **Managed Policies** | 9 AWS policies | Lambda, S3, API Gateway, CloudFront, IAM Read, Bedrock, DynamoDB, ACM, Route53 |
| **Inline Policy** | `github-actions-additional` | IAM write permissions for Terraform to manage roles |

#### Setup

Run the one-time setup script (defaults to `PatrickCmd/digital-twin`):

```bash
./scripts/setup-github-oidc.sh
# or with a custom repo:
./scripts/setup-github-oidc.sh owner/repo-name
```

The script auto-detects whether the OIDC provider already exists in your account and imports it if so. After apply, it backs up `github-oidc.tf` to `github-oidc.tf.backup` and prints the Role ARN needed for GitHub Secrets.

#### GitHub Repository Secrets

After running the OIDC script, set secrets automatically using the `gh` CLI:

```bash
./scripts/setup-github-secrets.sh            # defaults to us-east-1
./scripts/setup-github-secrets.sh us-west-2  # custom region
```

The script auto-detects `AWS_ACCOUNT_ID` and `AWS_ROLE_ARN` from your AWS account, sets all 3 secrets, and verifies with `gh secret list`. Requires `gh` CLI installed and authenticated (`gh auth login`).

| Secret | Value | Source |
|--------|-------|--------|
| `AWS_ROLE_ARN` | `arn:aws:iam::<account_id>:role/github-actions-twin-deploy` | Auto-detected |
| `DEFAULT_AWS_REGION` | `us-east-1` | Script argument (default) |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID | Auto-detected |

### GitHub Actions Workflows

Two workflows in `.github/workflows/`:

#### Deploy (`deploy.yml`)

- **Auto-triggers** on push to `main` or `day5-digital-twin-aws-terraform-cicd` branches (deploys to dev)
- **Manual trigger** via GitHub Actions UI with environment choice (dev/test/prod)
- Steps: checkout, OIDC auth, setup Python + uv + Terraform + Node.js, run `deploy.sh`, get outputs, invalidate CloudFront

#### Destroy (`destroy.yml`)

- **Manual trigger only** — requires environment selection and confirmation (type environment name)
- Steps: verify confirmation, checkout, OIDC auth, setup Terraform, run `destroy.sh`

## Teardown

```bash
./scripts/destroy.sh dev       # destroy dev
./scripts/destroy.sh prod      # destroy prod
```

See [Destroy Environment](#destroy-environment) above for details.
