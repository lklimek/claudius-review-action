# Learn action

The **Claudius Learn** action (`lklimek/claudius-review-action/learn@v1`) extracts reusable learnings from completed PR code reviews and saves them to MemCan. It runs after a PR merges, analyzes how developers responded to review findings (accepted, rejected, or ignored), and stores project-specific patterns so future reviews improve over time.

## Quick Start

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
    permissions: {}  # no checkout; the App token does all GitHub access
    env:
      ANTHROPIC_MODEL: sonnet
    steps:
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          client-id: ${{ vars.REVIEW_APP_CLIENT_ID }}
          private-key: ${{ secrets.REVIEW_APP_PRIVATE_KEY }}
          repositories: ${{ github.event.repository.name }}
          permission-pull-requests: write
      - uses: lklimek/claudius-review-action/learn@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ steps.app-token.outputs.token }}
          memcan_url: ${{ secrets.MEMCAN_URL }}
          memcan_api_key: ${{ secrets.MEMCAN_API_KEY }}
```

It uses the same GitHub App as the review ([GitHub App setup](github-app.md)). See [`examples/full.yml`](../examples/full.yml) for a workflow running both review and learn.

## Learn Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | **Yes** | | MemCan server URL (e.g., `http://host:8190`) |
| `memcan_api_key` | **Yes** | | MemCan API key for server authentication |
| `github_token` | **Yes** | | GitHub App installation token with Pull requests write, for reading PR data and adding heart reactions. An empty value fails the job |
| `project_name` | No | `${{ github.event.repository.name }}` | MemCan project scope |
| `min_review_comments` | No | `1` | Minimum Claudius inline review comments (threads) to trigger learning |
| `plugins` | No | `memcan@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude. The default covers reading the review data file and MemCan search/add; Bash is always denied |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided, plus `github_token`.

## Trigger Requirements

- Workflow must trigger on `pull_request: [closed]`
- Job condition should check `github.event.pull_request.merged == true`
- Job `permissions: {}`: learn needs no checkout, and all GitHub access (reading the PR, reviews and threads; heart reactions) goes through `github_token`
- App token: `permission-pull-requests: write` only (`write` for heart reactions, added by a step after the agent, not by the agent itself)

## Which reviews count

Learn recognizes reviews posted by the review action's GitHub App (`<app-slug>[bot]`). A review counts when both hold:

1. **Content** — its body contains either:
   - the claudius attribution footer that `post_pr_review.py` (claudius >= 8.2.0) appends, defined in [`lib/claudius.jq`](../lib/claudius.jq), or
   - a line starting with the review action's report link, `📊 **[View full HTML review report](`.
2. **Origin** (`trusted_origin` in [`lib/claudius.jq`](../lib/claudius.jq), also used by the review action) — its author is a bot account (a GitHub App installed on the repository), or has `OWNER`, `MEMBER` or `COLLABORATOR` association with the repository. The markers above are public, so on a public repository anyone can paste them into a review; the origin check keeps such reviews out of persistent memory.

Reviews and threads from other bots (Copilot, CodeRabbit) and humans are kept as context but never trigger learning or count towards `min_review_comments`. A thread is a Claudius thread when its first comment belongs to a Claudius review.

## What reaches the learning agent

The agent writes persistent memory, so its input is filtered before it runs:

- **PR title and body** — not passed to the agent; it sees the PR number and author login only.
- **Thread comments** — only comments with a trusted origin (bot, or `OWNER`/`MEMBER`/`COLLABORATOR`) are kept. A thread whose first comment is from anyone else is dropped whole; other untrusted replies are dropped individually and counted in the thread's `withheld_responses`, and the agent never classifies such a thread as ignored. Replies by outside contributors (including the PR author, when not a collaborator) are therefore never learned from, even when genuine.
- **Tools** — the agent reads the gathered data file (`/tmp/claudius-learn-*`) and uses MemCan search/add. Bash, WebFetch, WebSearch and claude-code-action's GitHub MCP servers (`mcp__github*`) are denied, so it has no shell, web or GitHub tools. Outside the job's working directory it can read only the data file. claude-code-action still places `github_token` in the agent's process environment (unreadable without a shell) and, when the workspace is a git checkout, in its git config (readable) — so run the learn job without a checkout.
- **Heart reactions** — added by a later step, only to comments in the data file by `OWNER`/`MEMBER`/`COLLABORATOR` users, at most 5 per PR.

Not protected:

- **Trusted authors** — any collaborator and any bot account (including third-party review bots installed on the repository) can steer learnings, as can untrusted text they quote.
- **Existing memories** — MemCan search results are taken at face value.

## Cost

The learn action exits early (no Claude run) when preconditions are not met (not merged, no Claudius reviews, fewer Claudius review comments than `min_review_comments`). When it does run, Sonnet or Haiku is recommended -- expect approximately $0.02-0.06 per invocation depending on PR size.
