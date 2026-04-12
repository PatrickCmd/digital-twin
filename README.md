# Digital Twin

An AI-powered digital twin that represents you in conversations. Built with a FastAPI backend (AWS Bedrock) and a Next.js frontend, deployed to AWS using Lambda, API Gateway, S3, and CloudFront.

**Live:** https://d2iaic6tzui2jf.cloudfront.net

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

## AWS Deployment

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
backend/       FastAPI app, Lambda handler, deployment scripts
frontend/      Next.js app (static export)
docs/          Course materials
memory/        Local conversation storage (dev only)
```
