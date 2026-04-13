# Digital Twin

An AI-powered digital twin that represents you in conversations. Built with a FastAPI backend (AWS Bedrock) and a Next.js frontend, deployed to AWS using Lambda, API Gateway, S3, and CloudFront.

**Live:** https://digital-twin.patrickcmd.dev/

## Architecture

```
Browser → CloudFront (HTTPS) → S3 (static frontend)
                                    ↓ API calls
                              API Gateway → Lambda (FastAPI)
                                              ├── AWS Bedrock (AI responses)
                                              └── S3 (conversation memory)
```

## Prerequisites

- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Node.js 18+
- AWS CLI configured with profiles `patrickcmd` (admin) and `aiengineer` (IAM user)
- Docker Desktop (for Lambda packaging)
- AWS Bedrock access enabled in your region

## Local Development

**Backend:**
```bash
cd backend
cp ../.env.example .env  # add your OPENAI_API_KEY
uv add -r requirements.txt
uv run uvicorn server:app --reload
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:3000

## AWS Deployment (Shell Scripts)

All deployment scripts are in `backend/bin/`. Run from the `backend/` directory. See [backend/README.md](backend/README.md) for detailed documentation on each script.

```bash
export AWS_ACCOUNT_ID=your_account_id

# 1. IAM setup (one-time, uses admin profile)
./bin/setup-iam.sh

# 2. Lambda
uv run deploy.py
./bin/deploy-lambda.sh
./bin/test-lambda.sh

# 3. S3 buckets
./bin/setup-s3.sh

# 4. API Gateway
./bin/setup-apigateway.sh
./bin/test-apigateway.sh

# 5. Frontend
./bin/deploy-frontend.sh

# 6. CloudFront
./bin/setup-cloudfront.sh
```

## Terraform Deployment (Recommended)

Infrastructure as Code using Terraform with workspace-based environments. See [terraform/README.md](terraform/README.md) for full details.

```bash
# Deploy
./scripts/deploy.sh           # dev (default)
./scripts/deploy.sh prod      # prod (uses prod.tfvars, custom domain)

# Invalidate CloudFront cache
./scripts/invalidate-cloudfront.sh dev

# Destroy
./scripts/destroy.sh dev
```

Environments and custom domains:

| Environment | Domain |
|-------------|--------|
| `prod` | `digital-twin.patrickcmd.dev` |
| `test` | `test-digital-twin.patrickcmd.dev` |
| `dev` | `dev-digital-twin.patrickcmd.dev` (optional) |

## CI/CD with GitHub Actions

Automated deployment and teardown via GitHub Actions using OIDC authentication (no long-lived AWS keys).

**Workflows:**

| Workflow | Trigger | Description |
|----------|---------|-------------|
| **Deploy** | Push to `main`, manual | Builds Lambda + frontend, applies Terraform, invalidates CloudFront |
| **Destroy** | Manual only | Empties S3 buckets and destroys all resources (requires confirmation) |

**One-time setup:**

```bash
# 1. Create S3 bucket + DynamoDB table for remote Terraform state
./scripts/setup-backend.sh

# 2. Create GitHub OIDC provider + IAM role in AWS
./scripts/setup-github-oidc.sh

# 3. Set GitHub repository secrets (AWS_ROLE_ARN, DEFAULT_AWS_REGION, AWS_ACCOUNT_ID)
./scripts/setup-github-secrets.sh
```

**Manual deploy via GitHub Actions UI:**
1. Go to Actions > Deploy Digital Twin
2. Click "Run workflow"
3. Select environment (dev/test/prod)

See [terraform/README.md](terraform/README.md) for full CI/CD documentation including remote state, OIDC auth, and workflow details.

## Shell Script Deployment

Manual step-by-step deployment using bash scripts. See [backend/README.md](backend/README.md) for detailed documentation on each script.

## Updating

```bash
# Backend changes
uv run deploy.py && ./bin/deploy-lambda.sh

# Frontend changes
./bin/deploy-frontend.sh && ./bin/invalidate-cloudfront.sh
```

## Teardown

```bash
./bin/teardown.sh
```

Removes all AWS resources (CloudFront, API Gateway, Lambda, S3, IAM). Requires confirmation.

## Project Structure

```
backend/       FastAPI app, Lambda handler, shell deployment scripts
frontend/      Next.js app (static export)
terraform/     Infrastructure as Code (modules, workspaces, environments)
scripts/       Terraform deploy, destroy, and invalidation scripts
docs/          Course materials
memory/        Local conversation storage (dev only)
```
