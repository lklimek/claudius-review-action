---
name: ci-pr-review
description: "Headless CI PR review flow for claudius-review-action: resolve fixed review threads, run claudius:grumpy-review with sequential static-only reviewers, post findings via gh, approve when clean. Use only inside claudius-review-action."
---

# CI PR Review

Single-shot headless run. Nothing resumes you after your turn ends: do not end it until `report.json` is written and the review is posted.

Context (env): `PR_NUMBER`, `GITHUB_REPOSITORY`, `BASE_REF`, `HEAD_REF`, `REPORT_DIR`, `SCRATCH_DIR`, `MEMCAN_AVAILABLE` (`true`/`false`).

## Ground rules

- **GitHub access**: `gh` CLI and the claudius `scripts/gh-*.sh` wrappers only. No GitHub MCP tools exist.
- **Files**: report output → `$REPORT_DIR`; every intermediate file (producer findings, contract copy, intermediate/merged JSON, review payload) → `$SCRATCH_DIR`. This replaces grumpy-review's `/data/tmp/grumpy-*` scratch dir. Never `mktemp`.
- **MemCan**: if `MEMCAN_AVAILABLE=true`, invoke `Skill(memcan:recall)` once and pass relevant hits into agent prompts. Otherwise never call memcan skills/tools and tell every agent so.
- **No web**: no WebSearch/WebFetch; tell every agent so.
- **PR comment tone**: Claudius persona — witty, confident, subtly snarky, always respectful and genuinely helpful. The report itself stays professional.
- Sub-agents have no conversation history: pass PR number, repo, base/head refs, comparison commands and file scope explicitly.

## 1. Previous review threads

`Skill(claudius:check-pr-comments)`. For each thread that IS fixed but NOT resolved: reply describing the fix, then resolve it. Remember which threads stay open (needed in §3–4).

## 2. Fresh review

`Skill(claudius:grumpy-review)` — never review the code yourself. CI overrides below take precedence over the skill text:

1. **Sequential**: spawn reviewers one at a time, in the foreground (never `run_in_background`); wait for each result before spawning the next. In the roster, state peers run before/after it, not concurrently.
2. **Models**: exactly as grumpy-review assigns per role (§2/§4) — always pass `model` on each `Agent` call. No uniform override.
3. **Static only** — put this verbatim in every spawn prompt:
   > Static review only. Never build, compile, run tests, linters, benchmarks or the application, and never install packages. Do not try to reproduce findings: report each one with evidence from reading the code, the diff and git history; mark unconfirmed findings as such (lower confidence) instead of dropping them. Do not create worktrees or check out other refs.
4. **Empty report is mandatory**: every reviewer writes its findings file, `[]` when it found nothing. You always run consolidation and write `$REPORT_DIR/report.json` — zero findings is a valid report with a positive `executive_summary`, never a reason to skip it.
5. **Render**: `--format html` into `$REPORT_DIR` (produces `report.html`); skip markdown.

## 3. Post the review

1. Head SHA: `gh pr view "$PR_NUMBER" --json headRefOid -q .headRefOid` (the workspace may be a merge commit).
2. Inline comments: MEDIUM+ findings only, skipping any already raised in a still-open thread. One comment per finding: `{path, line, side: "RIGHT", body}`; `line` must be inside the diff — otherwise put that finding in the review body instead.
3. Body: ALWAYS non-empty (one-line assessment + finding count). GitHub refuses to add a body later to a review created without one, which breaks the action's report-link step.
4. Event: `APPROVE` when no MEDIUM+ findings were posted and no unresolved threads remain (body e.g. "No unresolved findings — approved."); otherwise `COMMENT`.
5. Write `$SCRATCH_DIR/review.json` = `{commit_id, body, event, comments}` with the Write tool and post:
   ```bash
   gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" --method POST --input "$SCRATCH_DIR/review.json"
   ```
   On 422 about a comment position, move the offending comments into the body and retry. If `APPROVE` is rejected (token not allowed to approve), retry once with `COMMENT`. Never use `gh-post-review.sh` — it only creates unpublished drafts.
