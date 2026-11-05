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

### Not done / needs a decision from Patrick
- **Deploy.** Nothing has been deployed. Pushing to `main` deploys **dev**; production
  only updates through a manual "Deploy Digital Twin" workflow run with `prod` selected.
- **Shared rate limit.** `enable_rate_limit_table = true` creates a pay-per-request
  DynamoDB table so the limit is shared across Lambda instances. Off by default, so
  today the limit is per warm container only (API Gateway stage throttling still applies).
- **Contact email.** `enable_contact_email = true` with `contact_from_email` (a verified
  SES identity) and `contact_to_email`. Off by default; messages are still stored in S3.
- **True streaming.** Responses still arrive buffered because API Gateway HTTP API +
  Mangum cannot stream. The client already handles real streaming; the infra option is a
  Lambda Function URL with `RESPONSE_STREAM` plus the Lambda Web Adapter (replacing
  Mangum), or a different compute target. Not implemented.
- **Resume PDF.** `links.resume_pdf` is null; set it to a public URL to show the link.
- **Recruiter facts.** `remote_preference`, `work_authorization`, `notice_period` and
  `availability` are null in `profile.json`; fill them to show them on the card and let
  the twin answer them.
- **Eval run.** `eval_twin.py` could not be run here (no AWS credentials); run it locally
  or against the deployed API after the next deploy.
- **Terraform.** `terraform validate` passes; `plan`/`apply` were not run.
