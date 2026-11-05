# Follow-ups

Status as of 2026-11-05 after the improvement plan (`docs/improvement-plan.md`) shipped to
production. Everything below is something only Patrick can decide or do. Items are
ordered by value; each says what it changes, how to do it, and how to verify.

## Done

| Item | Evidence |
|------|----------|
| Plan merged, items 0 to 9 implemented | PRs #2 to #5 |
| Dev deployed and passing | `terraform-plan`/`deploy` runs green; eval 10/10 on dev |
| Prod deployed and passing | Page build 2026-11-05 07:03 UTC, `/health` 200, CORS closed to foreign origins, 2000-char cap enforced, eval 10/10 on prod |
| GitHub OIDC tightened, plan role created, secrets set | `setup-github-oidc.sh` + `setup-github-secrets.sh` run locally; deploy run 12 succeeded under the new trust policy |

## 1. Protect the `prod` GitHub Environment

Without this, anyone with push access can run a prod deploy that applies immediately.

- GitHub: **Settings > Environments > prod**.
- Add yourself under **Required reviewers**.
- Under **Deployment branches and tags**, allow only `main`.

Verify: run the Deploy workflow with `prod`; it should pause for your approval.

## 2. Fill the recruiter facts and resume link

`backend/data/profile.json` still has nulls. Null fields are hidden on the "For recruiters"
card and the twin defers to email for them.

```json
"recruiter_facts": {
  "remote_preference": null,
  "work_authorization": null,
  "notice_period": null,
  "availability": null
},
"links": { "resume_pdf": null }
```

- Fill the four strings (for example `"remote_preference": "Remote-first; open to EMEA time zones"`).
- For `resume_pdf`, put the PDF in `frontend/public/` (for example `resume.pdf`) and set
  `"resume_pdf": "/resume.pdf"`, or use any public URL.
- Bump `"knowledge_updated"` to today's date.

Verify locally: `cd frontend && npm run build` (the prebuild hook syncs the file), then
`cd backend && uv run pytest`. Deploy dev by merging to `main`; check the card and ask the
twin "What is your notice period?".

## 3. Tighten two soft answers

The eval passes, but two answers stretch the material:

- "What did you do at Sunbird AI?" is answered with the general summary (LLM systems on AWS)
  as if it were the Sunbird role description.
- "Which Kubernetes clusters have you run?" claims production Kubernetes experience because
  Kubernetes is in the stack list.

Fix by adding one short paragraph per topic to `backend/data/me/summary.md`, for example a
"Current role" section describing Sunbird AI, and a sentence stating your actual Kubernetes
experience. The twin can only say what is written there. Re-run:

```bash
cd backend && uv run eval_twin.py --api https://rt6dv8mwzc.execute-api.us-east-1.amazonaws.com
```

If you replace `linkedin.pdf`, run `cd backend && uv run build_knowledge.py` and commit the
regenerated `linkedin.md`.

## 4. Decide the two opt-in Terraform flags

Both are off, so no new billable resources exist. Set them in `terraform/prod.tfvars`
(and `terraform.tfvars` for dev if wanted) and merge; the plan workflow will show the diff on
the PR.

### `enable_rate_limit_table = true`

Creates a pay-per-request DynamoDB table so the 20-requests-per-10-minutes limit is shared
across Lambda instances. Today it is per warm container, so a burst can get 20 requests
through each container; API Gateway's stage throttle (burst 20, rate 10/s in prod) still
caps total load. Cost is effectively zero at this traffic.

### `enable_contact_email = true`

Emails "Leave a message" submissions through Amazon SES. Requires:

1. A verified SES identity for the sender. Simplest is to verify `p.walukagga@gmail.com`
   itself: **SES console > Identities > Create identity > Email address**, click the
   confirmation link.
2. Set in `prod.tfvars`:
   ```hcl
   enable_contact_email = true
   contact_from_email   = "p.walukagga@gmail.com"
   contact_to_email     = "p.walukagga@gmail.com"
   ```
3. If the account is still in the SES sandbox, recipients must also be verified; sending to
   yourself satisfies that.

Until enabled, messages are still stored in the memory bucket under `contact/<date>/`.
Feedback (thumbs up/down) is stored under `feedback/<date>/` regardless.

## 5. Watch the logs occasionally

One JSON line per chat, feedback and contact event goes to CloudWatch. Useful queries in
**CloudWatch > Logs Insights**, log group `/aws/lambda/twin-prod-api`:

```
# questions per day and median latency
filter event = "chat"
| stats count() as questions, pct(latency_ms, 50) as p50_ms by bin(1d)
```

```
# rate-limited clients
filter event = "rate_limited" | stats count() by client
```

```
# feedback ratings
filter event = "feedback" | stats count() by rating
```

Read the stored feedback and contact messages:

```bash
aws s3 ls s3://twin-prod-memory-<account-id>/feedback/ --recursive --profile patrickcmd
aws s3 ls s3://twin-prod-memory-<account-id>/contact/ --recursive --profile patrickcmd
```

The weekly Terraform Plan run (Mondays 06:17 UTC) fails if prod or dev has drifted from
`main`; a failure email from GitHub Actions is the signal.

## 6. Optional: true token streaming

Responses still arrive buffered because API Gateway HTTP API + Mangum cannot stream. The
client already renders incrementally and handles both modes. To enable real streaming:

- Replace Mangum with the Lambda Web Adapter and invoke the function through a Lambda
  Function URL with `RESPONSE_STREAM`, or move the backend to a container service.
- Route `/chat/stream` to the Function URL (or put both behind CloudFront).

Worth doing only if the 3 to 5 second wait for the first token becomes a complaint.

## 7. Optional hardening of the deploy role

`github-actions-twin-deploy` still carries nine AWS `FullAccess` managed policies plus IAM
write on `*`. Acceptable for a single-account personal project. If you want to scope it:
replace the attachments in `terraform/github-oidc.tf.backup` with inline policies limited
to resources named `twin-*`, re-run `./scripts/setup-github-oidc.sh`, and confirm a dev
deploy still succeeds.

## Routine commands

| Task | Command |
|------|---------|
| Deploy dev | merge to `main` |
| Deploy prod | Actions > Deploy Digital Twin > Run workflow > `prod` |
| Plan only | open a PR, or Actions > Terraform Plan > Run workflow |
| Backend tests | `cd backend && uv run pytest` |
| Grounding eval | `cd backend && uv run eval_twin.py --api <api url>` |
| Frontend checks | `cd frontend && npm run lint && npm run typecheck && npm run build` |
| Rebuild LinkedIn markdown | `cd backend && uv run build_knowledge.py` |
| Re-run OIDC bootstrap | `./scripts/setup-github-oidc.sh && ./scripts/setup-github-secrets.sh` |

API URLs: prod `https://rt6dv8mwzc.execute-api.us-east-1.amazonaws.com`, dev
`https://iip3j7ng96.execute-api.us-east-1.amazonaws.com`.
