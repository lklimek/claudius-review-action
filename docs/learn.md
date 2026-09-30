# Learn action

The **Claudius Learn** action (`lklimek/claudius-review-action/learn@v3`) extracts reusable learnings from completed PR code reviews and saves them to MemCan. It runs after a PR merges, analyzes how developers responded to review findings (accepted, rejected, or ignored), and stores project-specific patterns so future reviews improve over time.

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
    permissions:
      contents: read
      pull-requests: write
    env:
      ANTHROPIC_MODEL: sonnet
    steps:
      - uses: lklimek/claudius-review-action/learn@v3
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          memcan_url: ${{ secrets.MEMCAN_URL }}
          memcan_api_key: ${{ secrets.MEMCAN_API_KEY }}
```

See [`examples/full.yml`](../examples/full.yml) for a workflow running both review and learn.

## Learn Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | **Yes** | | MemCan server URL (e.g., `http://host:8190`) |
| `memcan_api_key` | **Yes** | | MemCan API key for server authentication |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI |
| `project_name` | No | `${{ github.event.repository.name }}` | MemCan project scope |
| `min_review_comments` | No | `1` | Minimum Claudius inline review comments (threads) to trigger learning |
| `plugins` | No | `memcan@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

## Trigger Requirements

- Workflow must trigger on `pull_request: [closed]`
- Job condition should check `github.event.pull_request.merged == true`
- `contents: read` and `pull-requests: write` permissions are needed (`write` for heart reactions)

## Which reviews count

Learn works with any `github_token` identity the review action posted under (`github-actions[bot]`, a GitHub App such as `<app>[bot]`, a machine user). A review counts when both hold:

1. **Content** — its body contains either:
   - the claudius attribution footer, `Co-authored by [Claudius the Magnificent](https://github.com/lklimek/claudius)` (added by claudius >= 8.2.0), or
   - a line starting with the review action's report link, `📊 **[View full HTML review report](`.
2. **Origin** — its author is a bot account (`github-actions[bot]` or a GitHub App installed on the repository), or has `OWNER`, `MEMBER` or `COLLABORATOR` association with the repository. The markers above are public, so on a public repository anyone can paste them into a review; the origin check keeps such reviews out of persistent memory. A machine user therefore needs to be a repository collaborator (any role, e.g. triage) or an organization member.

Reviews and threads from other bots (Copilot, CodeRabbit) and humans are kept as context but never trigger learning or count towards `min_review_comments`. A thread is a Claudius thread when its first comment belongs to a Claudius review.

## Cost

The learn action exits early (no Claude run) when preconditions are not met (not merged, no Claudius reviews, fewer Claudius review comments than `min_review_comments`). When it does run, Sonnet or Haiku is recommended -- expect approximately $0.02-0.06 per invocation depending on PR size.
