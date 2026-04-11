# Digital Twin Backend

FastAPI backend for the AI Digital Twin, deployable to AWS Lambda.

## Prerequisites

- AWS CLI configured with named profiles (`patrickcmd` for root/admin, `aiengineer` for IAM user)
- Docker Desktop (for building the Lambda deployment package)
- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- An OpenAI API key in a `.env` file (in `backend/` or project root):
  ```
  OPENAI_API_KEY=sk-...
  ```

## Local Development

```bash
cd backend
uv add -r requirements.txt
uv run uvicorn server:app --reload
```

The API will be available at `http://localhost:8000`.

## Deployment Scripts

All scripts are in `backend/bin/`. Run them from the `backend/` directory.

### 1. Setup IAM (`bin/setup-iam.sh`)

Creates the IAM group and permissions needed for the project. Run this **once** using the root/admin profile.

**AWS Profile:** `patrickcmd`

**What it does:**
- Creates the `TwinAccess` IAM group (idempotent — skips if it already exists)
- Attaches 6 policies: Lambda, S3, API Gateway, CloudFront, IAM ReadOnly, DynamoDB
- Adds the `aiengineer` IAM user to the group

```bash
./bin/setup-iam.sh
```

### 2. Deploy Lambda (`bin/deploy-lambda.sh`)

Creates or updates the Lambda function with your code and configuration.

**AWS Profile:** `aiengineer`

**What it does:**
- Creates the `twin-api-role` IAM execution role (if it doesn't exist)
- Creates or updates the `twin-api` Lambda function
- Uploads `lambda-deployment.zip` (direct for <50MB, via temp S3 bucket for larger)
- Configures: Python 3.12, x86_64, 512MB memory, 60s timeout
- Sets environment variables: `OPENAI_API_KEY`, `CORS_ORIGINS`, `USE_S3`, `S3_BUCKET`

**Before running**, build the deployment package:
```bash
uv run deploy.py
```

Then deploy:
```bash
./bin/deploy-lambda.sh
```

**Environment variables** (optional overrides):
| Variable | Default | Description |
|----------|---------|-------------|
| `DEFAULT_AWS_REGION` | `us-east-1` | AWS region |
| `AWS_ACCOUNT_ID` | — | Used in S3 bucket naming |
| `OPENAI_API_KEY` | loaded from `.env` | OpenAI API key |
| `S3_BUCKET` | `twin-memory-{AWS_ACCOUNT_ID}` | S3 bucket for conversation memory |

### 3. Test Lambda (`bin/test-lambda.sh`)

Invokes the deployed Lambda function with a health check event to verify it's working.

**AWS Profile:** `aiengineer`

**What it does:**
- Sends an API Gateway v2 proxy event to the `/health` endpoint
- Displays invoke metadata (status code, errors)
- Parses and shows the response body
- Reports success/failure

```bash
./bin/test-lambda.sh
```

**Expected output:**
```
=== Testing Lambda Function: twin-api (profile: aiengineer, region: us-east-1) ===

Invoking twin-api...
--- Invoke Metadata ---
{ "StatusCode": 200, "ExecutedVersion": "$LATEST" }

--- Parsed Body ---
{ "status": "healthy", "use_s3": true }

SUCCESS: Lambda health check passed!
```

### 4. Setup S3 Buckets (`bin/setup-s3.sh`)

Creates the memory and frontend S3 buckets and configures them for the project.

**AWS Profile:** `aiengineer`

**Requires:** `AWS_ACCOUNT_ID` environment variable (used as the unique bucket suffix).

**What it does:**
- Creates the memory bucket (`twin-memory-{AWS_ACCOUNT_ID}`) for conversation storage
- Updates the Lambda `S3_BUCKET` environment variable to point to the memory bucket
- Attaches `AmazonS3FullAccess` to the Lambda execution role
- Creates the frontend bucket (`twin-frontend-{AWS_ACCOUNT_ID}`) with public access enabled
- Enables static website hosting (index: `index.html`, error: `404.html`)
- Applies a public read bucket policy for serving static files

```bash
export AWS_ACCOUNT_ID=123456789012
./bin/setup-s3.sh
```

**Output includes:**
- Both bucket names
- The S3 website endpoint URL for the frontend

### 5. Setup API Gateway (`bin/setup-apigateway.sh`)

Creates an HTTP API Gateway with Lambda integration and routes.

**AWS Profile:** `aiengineer`

**Requires:** `AWS_ACCOUNT_ID` environment variable.

**What it does:**
- Creates an HTTP API (`twin-api-gateway`) or reuses existing
- Creates a Lambda proxy integration (payload format v2.0)
- Creates 5 routes: `GET /`, `GET /health`, `POST /chat`, `OPTIONS /{proxy+}`, `ANY /{proxy+}`
- Configures the `$default` stage with auto-deploy
- Configures CORS (allow all origins/headers/methods, max-age 300s)
- Grants API Gateway permission to invoke the Lambda function

All steps are idempotent — safe to re-run.

```bash
export AWS_ACCOUNT_ID=123456789012
./bin/setup-apigateway.sh
```

**Output includes:**
- API ID and invoke URL
- List of configured routes

### 6. Test API Gateway (`bin/test-apigateway.sh`)

Runs end-to-end tests against the live API Gateway endpoint.

**AWS Profile:** `aiengineer`

**What it does:**
- **GET /health** — verifies health check response
- **GET /** — verifies root endpoint
- **OPTIONS /chat** — verifies CORS preflight headers
- **POST /chat** — sends a test chat message and displays the response

```bash
./bin/test-apigateway.sh
```

### 7. Deploy Frontend (`bin/deploy-frontend.sh`)

Builds the Next.js frontend as a static export and uploads it to the S3 frontend bucket.

**AWS Profile:** `aiengineer`

**Requires:** `AWS_ACCOUNT_ID` environment variable.

**What it does:**
- Installs npm dependencies
- Runs `npm run build` to produce a static export (`out/` directory)
- Syncs the build output to `s3://twin-frontend-{AWS_ACCOUNT_ID}/` with `--delete` to remove stale files

```bash
export AWS_ACCOUNT_ID=123456789012
./bin/deploy-frontend.sh
```

**Output includes:**
- File count from the build
- S3 website endpoint URL

### 8. Setup CloudFront (`bin/setup-cloudfront.sh`)

Creates a CloudFront distribution for the frontend and updates Lambda CORS settings.

**AWS Profile:** `aiengineer`

**Requires:** `AWS_ACCOUNT_ID` environment variable.

**What it does:**
- Creates a CloudFront distribution (or reuses existing) with:
  - Custom origin pointing to S3 website endpoint (HTTP only)
  - `CachingOptimized` managed cache policy
  - Viewer protocol: redirect HTTP to HTTPS
  - Price class: North America & Europe only (cost savings)
  - Default root object: `index.html`
  - No WAF (saves $14/month)
- Updates Lambda `CORS_ORIGINS` to the CloudFront URL (`https://`, no trailing `/`)
- Creates an initial cache invalidation for `/*`

Idempotent — safe to re-run.

```bash
export AWS_ACCOUNT_ID=123456789012
./bin/setup-cloudfront.sh
```

**Output includes:**
- Distribution ID, domain, and full URL
- Note: CloudFront takes 5-15 minutes to deploy globally

### 9. Invalidate CloudFront Cache (`bin/invalidate-cloudfront.sh`)

Creates a CloudFront cache invalidation so updated content is served immediately.

**AWS Profile:** `aiengineer`

**What it does:**
- Finds the distribution automatically by its comment tag
- Creates an invalidation for the specified path(s)

```bash
# Invalidate everything (default)
./bin/invalidate-cloudfront.sh

# Invalidate a specific path
./bin/invalidate-cloudfront.sh /index.html
```

## Typical Workflow

```bash
# 1. One-time IAM setup (as admin)
./bin/setup-iam.sh

# 2. Build the deployment package
uv run deploy.py

# 3. Deploy to Lambda
./bin/deploy-lambda.sh

# 4. Verify the deployment
./bin/test-lambda.sh

# 5. Create S3 buckets (memory + frontend)
export AWS_ACCOUNT_ID=123456789012
./bin/setup-s3.sh

# 6. Setup API Gateway
./bin/setup-apigateway.sh

# 7. Test API Gateway end-to-end
./bin/test-apigateway.sh

# 8. Build and deploy frontend
./bin/deploy-frontend.sh

# 9. Setup CloudFront (sets up HTTPS + updates CORS)
./bin/setup-cloudfront.sh

# 10. After future frontend updates, invalidate cache
./bin/deploy-frontend.sh
./bin/invalidate-cloudfront.sh
```

## Teardown

To remove **all** provisioned AWS resources when you're done testing:

```bash
export AWS_ACCOUNT_ID=123456789012
./bin/teardown.sh
```

**What it deletes (in order):**

1. CloudFront distribution (disables first, waits for deployment, then deletes)
2. API Gateway
3. Lambda function
4. Lambda execution role (detaches all policies first)
5. S3 memory bucket (empties, then deletes)
6. S3 frontend bucket (empties, then deletes)
7. IAM group `TwinAccess` (removes users, detaches policies, then deletes)

The script requires confirmation before proceeding and skips any resources that don't exist.

**Note:** CloudFront must be disabled before deletion, which can take several minutes. The script handles this automatically.
