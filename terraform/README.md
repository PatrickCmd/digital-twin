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

## Teardown

```bash
./scripts/destroy.sh dev       # destroy dev
./scripts/destroy.sh prod      # destroy prod
```

See [Destroy Environment](#destroy-environment) above for details.
