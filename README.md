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
cp .env.example .env  # set DEFAULT_AWS_REGION / BEDROCK_MODEL_ID as needed
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

**Checks:**
```bash
cd backend && uv run pytest            # API and prompt tests (no AWS needed)
cd backend && uv run eval_twin.py      # grounding regression questions (needs AWS creds)
cd backend && uv run eval_twin.py --api https://<api-id>.execute-api.us-east-1.amazonaws.com
cd frontend && npm run lint && npm run typecheck && npm run build
```

## Profile data (`backend/data/profile.json`)

All facts about Patrick that the UI and the prompt use live in one file,
`backend/data/profile.json`. The frontend imports a synced copy
(`frontend/content/profile.json`, refreshed by `npm run sync-profile`, which also runs
before `npm run dev` and `npm run build`). Edit the source file only.

| Field | Used for |
|-------|----------|
| `full_name`, `name`, `title`, `headline`, `location`, `timezone`, `email` | Header, metadata, JSON-LD, system prompt |
| `links.github`, `links.linkedin`, `links.website`, `links.resume_pdf` | Header links (`null` hides a link) |
| `specialties`, `certifications` | Prompt and recruiter card |
| `career_start` (`YYYY-MM`) | Years of experience, computed at build/run time |
| `recruiter_facts.*` | "For recruiters" card; `null` fields are hidden and the twin defers on them |
| `suggested_questions` | Chips in the empty chat state |
| `knowledge_updated` | "What this twin knows" line and sitemap |

The rest of the knowledge base is `backend/data/me/summary.md`, `backend/data/me/linkedin.pdf`
and `backend/data/style.txt`, all concatenated into the system prompt in `backend/context.py`.

## Environment variables

Backend (`backend/.env` locally; set by Terraform on Lambda):

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEFAULT_AWS_REGION` | `us-east-1` | Bedrock / SES region |
| `BEDROCK_MODEL_ID` | `global.amazon.nova-2-lite-v1:0` | Model used by the Converse API |
| `CORS_ORIGINS` | `http://localhost:3000` | Comma-separated browser origins |
| `USE_S3`, `S3_BUCKET`, `MEMORY_DIR` | local files in `../memory` | Conversation, feedback and contact storage |
| `MAX_MESSAGE_CHARS` | `2000` | Chat message length cap |
| `MAX_SESSION_MESSAGES` | `60` | Stored messages per session before a new chat is required |
| `RATE_LIMIT_REQUESTS`, `RATE_LIMIT_WINDOW_SECONDS` | `20`, `600` | Per-client limit on chat, feedback and contact |
| `RATE_LIMIT_TABLE` | unset | DynamoDB table for a limit shared across Lambda instances |
| `SES_FROM_EMAIL`, `SES_TO_EMAIL` | unset | Email contact-form messages via SES (sender must be a verified identity) |

Frontend: `NEXT_PUBLIC_API_URL` (written to `frontend/.env.production` by `scripts/deploy.sh`).

Terraform variables that create extra resources are off by default:
`enable_rate_limit_table` (DynamoDB) and `enable_contact_email` with
`contact_from_email` / `contact_to_email` (SES). See `terraform/variables.tf`.

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
| **Terraform Plan** | Pull requests, weekly, manual | Builds the Lambda package and runs `terraform plan` for dev and prod; posts the plan on the PR; weekly run fails on drift. Never applies. |
| **Deploy** | Push to `main` (deploys **dev**), manual | Builds Lambda + frontend, applies Terraform, invalidates CloudFront. `prod` waits for approval in the GitHub Environment |
| **Destroy** | Manual only | Empties S3 buckets and destroys all resources (requires confirmation) |

**One-time setup:**

```bash
# 1. Create S3 bucket + DynamoDB table for remote Terraform state
./scripts/setup-backend.sh

# 2. Create GitHub OIDC provider + IAM role in AWS
./scripts/setup-github-oidc.sh

# 3. Set GitHub repository secrets (AWS_ROLE_ARN, AWS_PLAN_ROLE_ARN, DEFAULT_AWS_REGION, AWS_ACCOUNT_ID)
./scripts/setup-github-secrets.sh

# 4. In GitHub: Settings > Environments > prod > add yourself as a required reviewer
```

Already set up before the plan role existed? Re-run steps 2 and 3: the OIDC script adds the
`github-actions-twin-plan` role and tightens the deploy role's trust policy to the
`dev`/`test`/`prod` environments.

**Manual deploy via GitHub Actions UI:**
1. Go to Actions > Deploy Digital Twin
2. Click "Run workflow"
3. Select environment (dev/test/prod)

Note: a push to `main` only deploys **dev**. Production (`digital-twin.patrickcmd.dev`)
updates only when the workflow is run manually with `prod` selected.

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
docs/          Course materials and docs/improvement-plan.md (review + roadmap)
memory/        Local conversation, feedback and contact storage (dev only)
```
