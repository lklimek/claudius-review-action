# Claudius PR Review Action

A reusable GitHub composite action that wraps [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) for AI-powered PR reviews with the Claudius pipeline: it resolves fixed review threads, runs a multi-specialist static review, posts inline findings and approves the PR when nothing unresolved remains. Requires claudius >= 8.2.0 (installed at run time).

The action runs under your own GitHub App: the calling workflow mints a short-lived installation token and passes it as `github_token`, so every review, reply and label change is posted as `<app-slug>[bot]`.

## Getting started

### 1. Create and install a GitHub App

Under **Settings → Developer settings → GitHub Apps → New GitHub App** (on your user or organization):

- **Webhook**: untick **Active**.
- **Repository permissions**: Contents **Read-only**, Issues **Read and write**, Pull requests **Read and write** (Metadata: Read-only is implicit). Nothing else.
- Create the App, note its **Client ID** and generate a **private key** (`.pem`).
- **Install App** on the repositories to review.

### 2. Store the credentials

In the reviewed repository (or its organization), **Settings → Secrets and variables → Actions**:

| Kind | Name | Value |
|------|------|-------|
| Variable | `REVIEW_APP_CLIENT_ID` | the App's Client ID |
| Secret | `REVIEW_APP_PRIVATE_KEY` | the full contents of the `.pem` file |
| Secret | `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token (or `ANTHROPIC_API_KEY` with `anthropic_api_key`) |

### 3. Add the workflow

Label a PR `claudius-review` to start a review; new pushes re-review while the label stays. Full file: [`examples/minimal.yml`](examples/minimal.yml).

```yaml
on:
  pull_request:
    types: [labeled, synchronize]

jobs:
  review:
    if: >
      github.event.pull_request.draft == false &&
      (
        (github.event.action == 'labeled' && github.event.label.name == 'claudius-review') ||
        (github.event.action == 'synchronize' && contains(github.event.pull_request.labels.*.name, 'claudius-review'))
      )
    # Job-level, so events skipped by `if:` (e.g. an unrelated label) never
    # cancel a running review; a new push to a reviewed PR supersedes it.
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
      cancel-in-progress: true
    runs-on: ubuntu-latest
    timeout-minutes: 30  # keep <= 60: the App token expires after 1 hour
    permissions:
      contents: read  # checkout only; the App token does all GitHub writes
    steps:
      # First step, so the token outlives the job.
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          client-id: ${{ vars.REVIEW_APP_CLIENT_ID }}
          private-key: ${{ secrets.REVIEW_APP_PRIVATE_KEY }}
          repositories: ${{ github.event.repository.name }}
          permission-contents: read
          permission-issues: write
          permission-pull-requests: write
      - uses: lklimek/claudius-review-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ steps.app-token.outputs.token }}
```

[`examples/full.yml`](examples/full.yml) shows every input, the review-request trigger and the learn job.

## Permissions

- **Job `permissions:`**: `contents: read` only. The job's own token is used just to check out the PR; the App token does every GitHub write.
- **App token**: scoped to the current repository with Contents read, Issues write and Pull requests write.
- **No `id-token: write`**: `claude-code-action` only needs OIDC to mint a token of its own, which it never does when `github_token` is passed, and the permission would let any step (including the review agent) mint OIDC tokens.
- **No fallback**: a missing or misconfigured App fails the job instead of silently running under another identity. See [Failure modes](docs/github-app.md#failure-modes).

Only actors with write/admin access can trigger a review by default; see [Triggers](docs/triggers.md) for bots and the review-request mode.

## Inputs

Required: one Claude credential (`anthropic_api_key` or `claude_code_oauth_token`) and `github_token` set to the App token. Everything else is optional.

| Group | Inputs |
|-------|--------|
| Credentials | `anthropic_api_key`, `claude_code_oauth_token`, `github_token` |
| Trigger | `trigger_label`, `remove_label_on_success`, `reviewer_login`, `remove_review_request_on_success`, `allowed_non_write_users` |
| Model and plugins | `model` (default `sonnet`), `claude_agent`, `plugins`, `plugin_marketplaces`, `prompt_extra` |
| MemCan | `memcan_url`, `memcan_api_key` |
| Checkout | `checkout`, `fetch_depth` |
| Tools and CLI | `allowed_tools`, `claude_extra_args` |
| Artifacts | `report_retention_days`, `upload_transcripts`, `transcripts_recipients`, `transcript_retention_days` |
| Debug | `debug_output` (may leak secrets into logs) |

Outputs: `report_artifact_name`, `transcripts_artifact_name`. Defaults, descriptions and environment variables: [Configuration reference](docs/configuration.md).

## More

- [GitHub App setup](docs/github-app.md): key handling, token lifetime, failure modes, thread resolution
- [Triggers](docs/triggers.md): label, review request, non-write actors
- [Configuration reference](docs/configuration.md): all inputs, outputs, env vars
- [How it works](docs/how-it-works.md): review flow, tool allowlist, MemCan preflight
- [Learn action](docs/learn.md): extract review learnings into MemCan after merge

---

Built by [Claudius the Magnificent](https://github.com/lklimek/claudius)
