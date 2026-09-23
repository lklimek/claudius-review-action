# Claudius PR Review Action

A reusable GitHub composite action that wraps [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) into a single step for AI-powered PR code reviews. It runs the Claudius review pipeline — checking previous comments, performing a fresh multi-specialist code review, posting inline findings, and optionally approving clean PRs.

## Minimal Usage

```yaml
name: Claudius Review
on:
  pull_request:
    types: [labeled, synchronize]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  review:
    if: >
      github.event.pull_request.draft == false &&
      (
        (github.event.action == 'labeled' && github.event.label.name == 'claudius-review') ||
        (github.event.action == 'synchronize' && contains(github.event.pull_request.labels.*.name, 'claudius-review'))
      )
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      issues: write
      pull-requests: write
      id-token: write
    steps:
      - uses: lklimek/claudius-review-action@v2
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Extended Usage

```yaml
name: Claudius Review
on:
  pull_request:
    types: [labeled, synchronize]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  review:
    if: >
      github.event.pull_request.draft == false &&
      (
        (github.event.action == 'labeled' && github.event.label.name == 'ai-review') ||
        (github.event.action == 'synchronize' && contains(github.event.pull_request.labels.*.name, 'ai-review'))
      )
    runs-on: ubuntu-latest
    timeout-minutes: 45
    permissions:
      contents: read
      issues: write
      pull-requests: write
      id-token: write
    env:
      CLAUDE_CODE_MAX_TURNS: "200"
      CLAUDE_CODE_EFFORT_LEVEL: high
    steps:
      - uses: lklimek/claudius-review-action@v2
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: sonnet
          upload_transcripts: "true"
          transcripts_recipients: github:your-login
          memcan_url: ${{ secrets.MEMCAN_URL }}
          memcan_api_key: ${{ secrets.MEMCAN_API_KEY }}
          trigger_label: ai-review
          prompt_extra: |
            Focus especially on security issues and SQL injection vectors.
            This is a monorepo — review only files under packages/.
          plugins: |
            claudius@lklimek
            claudash@lklimek
            memcan@lklimek
            my-custom-plugin@my-org
          plugin_marketplaces: |
            https://github.com/lklimek/agents.git
            https://github.com/my-org/agents.git
```

## Triggering by Review Request

Instead of a label, you can trigger a review by requesting the bot account
as a PR reviewer:

```yaml
name: Claudius Review
on:
  pull_request:
    types: [review_requested, synchronize]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  review:
    if: >
      github.event.pull_request.draft == false &&
      (
        (github.event.action == 'review_requested' && github.event.requested_reviewer.login == 'Claudius-Maginificent') ||
        (github.event.action == 'synchronize' && contains(github.event.pull_request.requested_reviewers.*.login, 'Claudius-Maginificent'))
      )
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      issues: write
      pull-requests: write
      id-token: write
    steps:
      - uses: lklimek/claudius-review-action@v2
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          remove_label_on_success: false
          reviewer_login: Claudius-Maginificent
```

`review_requested` fires the moment the account is requested as a reviewer;
the `synchronize` branch re-triggers on new pushes as long as that request is
still pending. Set `remove_label_on_success: false` since there's no trigger
label in this mode — but set `reviewer_login` to the same account named in
the `if:` condition above, or the pending request never clears: the review
itself is posted under whichever GitHub identity `github_token` authenticates
as, not under `reviewer_login`, so GitHub does **not** auto-clear that
account's own pending review request the way it would if it had reviewed
itself. Without `reviewer_login` set, the request stays forever and every
subsequent push re-triggers a full review. To get a fresh review later, just
re-request the review; that fires a new `review_requested` event instead of
re-applying a label.

Requires the reviewer account to be an actual collaborator (not just
implicit public-repo read access) with at least `read`/`triage` permission —
otherwise it won't show up in GitHub's reviewer picker at all.

This mode is still gated by the same write-access preflight described in
["Triggering by non-write actors"](#triggering-by-non-write-actors) above —
it checks `github.event.sender.login` (whoever requested the review, or
pushed on `synchronize`), not the reviewer being requested. If that person
or bot doesn't have `write`/`admin` access, add them to
`allowed_non_write_users` the same way you would for the label trigger.

## How It Works

The action installs a small `ci-pr-review` skill and `claudius-ci-reviewer`
agent (from [`claude/`](claude)) into the runner's `~/.claude`, then asks
Claude to run that skill. The skill:

1. runs `claudius:check-pr-comments` — replies to and resolves threads that
   are already fixed;
2. runs `claudius:grumpy-review` with CI overrides — reviewers run **in
   parallel**, do **static review only** (no builds, tests or
   reproduction attempts; unconfirmed findings are reported, not dropped),
   and a report is **always** written, even when nothing was found;
3. posts MEDIUM+ findings as inline comments via `gh`, and approves the PR
   when nothing is left unresolved.

All GitHub access goes through the `gh` CLI (no GitHub MCP server).

This repository reviews its own non-draft PRs with the PR's version of the
action — see [`.github/workflows/claudius-review.yml`](.github/workflows/claudius-review.yml).

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | No | `""` | MemCan server URL (e.g., `http://host:8190`) |
| `memcan_api_key` | No | `""` | MemCan API key for server authentication |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI |
| `allowed_non_write_users` | No | `""` | Comma-separated usernames (or `*`) allowed to trigger the review without write/admin access — e.g. a triage-permission bot that only applies the trigger label. Passed through to `claude-code-action`; requires `github_token` |
| `claude_agent` | No | `claudius-ci-reviewer` | Main-thread agent. The default is the lightweight coordinator shipped in [`claude/agents`](claude/agents); a plugin agent (e.g. `claudius:claudius`) uses its own frontmatter model instead of `model` |
| `model` | No | `sonnet` | Coordinator (main-thread) model. Reviewer sub-agents always use the per-role models from `claudius:grumpy-review`. Empty = Claude Code default |
| `plugins` | No | `claudius@lklimek`, `claudash@lklimek`, `memcan@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `prompt_extra` | No | `""` | Additional instructions appended to core prompt |
| `trigger_label` | No | `claudius-review` | Label to remove on success |
| `remove_label_on_success` | No | `true` | Whether to remove trigger label |
| `reviewer_login` | No | `""` | GitHub login to clear from pending review requests on success (review-request trigger mode only). No-op when empty |
| `remove_review_request_on_success` | No | `true` | Whether to clear `reviewer_login`'s pending review request |
| `checkout` | No | `true` | Whether action handles git checkout (the PR head commit). If `false`, check out the PR head yourself with enough history to reach `origin/<base>` |
| `fetch_depth` | No | `0` | Git fetch depth (only if checkout=true). Reviewers diff against `origin/<base>`, so keep `0` or deep enough to reach the merge base |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags (appended to built-in args) |
| `report_retention_days` | No | `14` | Artifact retention days |
| `upload_transcripts` | No | `false` | Upload Claude Code session transcripts (coordinator + sub-agents, plus the execution log) as a GPG-encrypted artifact. Requires `transcripts_recipients` — the action fails instead of uploading plaintext |
| `transcript_retention_days` | No | `7` | Retention days for the transcripts artifact |
| `transcripts_recipients` | No | `""` | Newline-separated GPG public keys to encrypt transcripts to: `github:<login>` (keys from `github.com/<login>.gpg`), an `https://` URL to an armored key, or a fingerprint (from keys.openpgp.org). Full 40-hex fingerprints only. Public keys only — no secret needed. Decrypt: `gpg -d claude-transcripts.tar.gz.gpg \| tar xz` |
| `debug_output` | No | `false` | Show full raw Claude Code JSON output in the job log. Also turns on automatically when GitHub's "Enable debug logging" re-run checkbox is checked. **WARNING: may leak secrets/tokens into publicly-visible Actions logs — enable only for troubleshooting**, and be aware that checkbox trips the same warning |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

### Triggering by non-write actors

By default, only actors with `admin` or `write` repo access can trigger a
review (add/re-add the trigger label, or push to an already-labeled PR). This
is enforced twice: a fast preflight in this action, and again inside
`claude-code-action` itself — both exist because the underlying action's own
rejection is an opaque error surfacing ~40s into setup.

If a bot or service account with only `triage` permission (e.g. one that
applies the trigger label on your behalf) needs to trigger reviews, add it to
`allowed_non_write_users`:

```yaml
with:
  allowed_non_write_users: my-triage-bot
```

Use a comma-separated list for multiple accounts, or `*` to allow any actor
(not recommended on public repos — see the input's description in
[`action.yml`](action.yml) for the security caveat).

## Claude Code Environment Variables

Claude Code behavior (effort, turns, etc.) is controlled via environment variables set at the **workflow level** — except the coordinator model, which is the `model` input (see below). The action's pre-flight step logs all recognized variables — check the "Claude Code environment" group in the workflow output for the effective configuration.

Set them in your workflow's `env:` block:

```yaml
jobs:
  review:
    env:
      CLAUDE_CODE_MAX_TURNS: "150"
      CLAUDE_CODE_EFFORT_LEVEL: high
```

The coordinator model is set by the `model` input (default `sonnet`), not by
`ANTHROPIC_MODEL`. Reviewer sub-agents get their models per role from
`claudius:grumpy-review`; leave `CLAUDE_CODE_SUBAGENT_MODEL` unset.

## Outputs

| Output | Description |
|--------|-------------|
| `report_artifact_name` | Name of the uploaded review report artifact |
| `transcripts_artifact_name` | Name of the uploaded transcripts artifact (when `upload_transcripts` is `true`) |

## Required Permissions

```yaml
permissions:
  contents: read
  issues: write
  pull-requests: write
  id-token: write
```

## Learn Action

The **Claudius Learn** action (`lklimek/claudius-review-action/learn@v2`) extracts reusable learnings from completed PR code reviews and saves them to MemCan. It runs after a PR merges, analyzes how developers responded to review findings (accepted, rejected, or ignored), and stores project-specific patterns so future reviews improve over time.

### Quick Start

```yaml
name: Claudius Learn
on:
  pull_request:
    types: [closed]

jobs:
  learn:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      pull-requests: write
    env:
      ANTHROPIC_MODEL: sonnet
    steps:
      - uses: lklimek/claudius-review-action/learn@v2
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          memcan_url: ${{ secrets.MEMCAN_URL }}
          memcan_api_key: ${{ secrets.MEMCAN_API_KEY }}
```

See [`examples/learn.yml`](examples/learn.yml) for a standalone workflow and [`examples/combined.yml`](examples/combined.yml) for both review and learn in one file.

### Learn Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | **Yes** | | MemCan server URL (e.g., `http://host:8190`) |
| `memcan_api_key` | **Yes** | | MemCan API key for server authentication |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI |
| `project_name` | No | `${{ github.event.repository.name }}` | MemCan project scope |
| `min_review_comments` | No | `1` | Minimum review comments to trigger learning |
| `plugins` | No | `memcan@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

### Trigger Requirements

- Workflow must trigger on `pull_request: [closed]`
- Job condition should check `github.event.pull_request.merged == true`
- `contents: read` and `pull-requests: write` permissions are needed (`write` for heart reactions)

### Cost

The learn action exits early (zero cost) when preconditions are not met (no claude[bot] reviews, not merged, below comment threshold). When it does run, Sonnet or Haiku is recommended -- expect approximately $0.02-0.06 per invocation depending on PR size.

---

Built by [Claudius the Magnificent](https://github.com/lklimek/claudius)
