# Changelog

## Unreleased (branch `claude/gifted-franklin-u0gfw0`)

Implements the plan in `docs/improvement-plan.md`. One commit per item.

### 0. Housekeeping
- Lint is green again (unescaped entities, anonymous export); avatar uses `next/image`.
- Removed 8.3 MB of unused avatar images and starter SVGs from `frontend/public/`.
- Removed the unused `openai` dependency and `OPENAI_API_KEY` references.
- Dropped the merged feature branch from the deploy workflow triggers.

### 1. Profile data
- `backend/data/profile.json` replaces `facts.json` and is the single source of truth
  (headline, links, `career_start`, certifications, recruiter facts, suggested questions,
  `knowledge_updated`). Email is `p.walukagga@gmail.com` everywhere.
- `frontend/content/profile.ts` imports a synced copy (`npm run sync-profile`, run
  automatically before `dev` and `build`).
- Landing header shows avatar, name, title, headline, links and an AI disclosure.
- Six suggested-question chips in the empty state.

### 2. Grounding
- System prompt now goes through the Converse `system` parameter.
- Prompt rewritten: first person only, answer only from the material, no invented role
  descriptions / tools / metrics, no inferred work authorization, no headings, no
  trailing questions, computed years of experience, recruiter logistics marked
  known / NOT KNOWN. Temperature lowered to 0.4.
- `backend/eval_twin.py`: ten regression questions from the live review.
- Unit tests (`uv run pytest`) for the prompt and Bedrock call shape.

### 3. Hardening
- Message length cap (2000), UUID session ids, non-blank messages; JSON error bodies
  with codes.
- Per-client rate limit (20 / 10 min) on chat, feedback and contact routes. Memory store
  by default; DynamoDB store when `RATE_LIMIT_TABLE` is set.
- Sessions capped at 60 stored messages (409 `session_full`).
- Structured JSON log line per chat / feedback / contact for CloudWatch Logs Insights.
- API Gateway CORS restricted to the site origins; Lambda IAM reduced to
  `bedrock:InvokeModel*` plus the memory bucket.

### 4. Chat UX
- Viewport-filling layout, pane-level auto-scroll, auto-growing textarea, Enter / Shift+Enter,
  Stop button, New chat, localStorage persistence (`digital-twin:v1`), error bubble with
  Retry, markdown links in new tabs, dark mode, aria-live and labelled controls,
  reduced-motion support.
- Thumbs up/down per answer → `POST /feedback` → `feedback/<date>/<uuid>.json` in the
  memory bucket.

### 5. Recruiter path
- "For recruiters" quick-facts card (null fields hidden) in the empty state and in a
  header dialog.
- "Leave a message" form → `POST /contact` → `contact/<date>/<uuid>.json`, emailed via
  Amazon SES when configured. Honeypot field.

### 6. SEO and polish
- Title, description, canonical, OpenGraph / Twitter tags, generated `public/og.png`,
  Person JSON-LD, `robots.txt`, `sitemap.xml`, theme-color.

### 7. Terraform in CI (plan on PR, apply stays in deploy)
- `terraform-plan.yml`: on pull requests builds the Lambda package and runs
  `fmt -check`, `validate` and `plan` for dev and prod against the existing S3 +
  DynamoDB backend, posts one comment per environment on the PR, and runs weekly as a
  drift check (fails on changes). Manual runs can plan any environment. Never applies.
- `deploy.yml` / `destroy.yml`: pinned Terraform 1.9.8, non-interactive flags,
  per-environment concurrency group so applies and destroys never overlap;
  `deploy.sh` uses `fmt -check` in CI and `-lock-timeout=5m`.
- OIDC bootstrap (`terraform/github-oidc.tf.backup`): deploy role trust pinned to
  `environment:dev|test|prod` subjects; new read-only `github-actions-twin-plan` role
  (ReadOnlyAccess + state bucket read + lock table). Setup scripts create it and set
  `AWS_PLAN_ROLE_ARN`. Until the scripts are re-run, the plan workflow falls back to
  `AWS_ROLE_ARN`.
- `required_version` pinned to `>= 1.9.0, < 2.0.0`.

### 8. Fix: Lambda crashed at startup after the first deploy
- Every route on dev returned API Gateway's 500 after the merge. The freshly built
  package pulled the newest `pymupdf4llm`, which now depends on `pymupdf-layout`,
  `onnxruntime` and `numpy` (~190 MB) and loads a layout model when the PDF is converted
  at import time.
- The LinkedIn PDF is now converted once at build time (`build_knowledge.py`, run by
  `deploy.py`) and committed as `data/me/linkedin.md`; `requirements.txt` for the Lambda
  no longer includes `pymupdf4llm`/`pypdf`, and the package excludes the PDF.
- `eval_twin.py --api` now prints the HTTP error body instead of a traceback.
- One-time setup scripts (`setup-backend.sh`, `setup-github-oidc.sh`,
  `setup-github-secrets.sh`) use the `patrickcmd` AWS profile (override with
  `AWS_PROFILE`) for `aws` calls and pass it to Terraform via `TF_VAR_aws_profile`.

### 9. Fix: bootstrap scripts failed on the S3 backend block
- `setup-backend.sh` and `setup-github-oidc.sh` ran a bare `terraform init`, which
  now fails because `backend.tf` declares an S3 backend without bucket/key/region. They
  now share `scripts/bootstrap-common.sh`: a temporary `backend_override.tf` switches
  to a local backend (`terraform/bootstrap.tfstate`, gitignored), the admin profile and
  `us-east-1` are defaults, and existing AWS resources are imported before `apply` so
  the scripts are safe to re-run.

### Status (2026-11-05)
- Dev and prod are deployed from `main`; the grounding eval passes 10/10 on both.
- OIDC bootstrap re-run: plan role created, deploy role trust tightened, secrets set.
- Remaining decisions and optional work are tracked in `docs/follow-ups.md`
  (prod environment protection, recruiter facts and resume link, two soft answers,
  the DynamoDB rate-limit and SES contact-email flags, log queries, true streaming,
  deploy-role hardening).
