# Claudius PR Review Action

A reusable GitHub composite action that wraps [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) for AI-powered PR reviews with the Claudius pipeline: it resolves fixed review threads, runs a multi-specialist static review, posts inline findings and approves the PR when nothing unresolved remains. Requires claudius >= 8.2.0 (installed at run time).

## Usage

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
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      issues: write
      pull-requests: write
      id-token: write
    steps:
      - uses: lklimek/claudius-review-action@v3
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

[`examples/full.yml`](examples/full.yml) shows every input, the review-request trigger, GitHub App token minting and the learn job.

## Required permissions

`contents: read`, `issues: write`, `pull-requests: write`, `id-token: write`. Only actors with write/admin access can trigger a review by default; see [Triggers](docs/triggers.md) for bots and the review-request mode.

## Inputs

One credential is required: `anthropic_api_key` or `claude_code_oauth_token`. Everything else is optional.

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

## GitHub App identity

The review is posted as whichever identity `github_token` authenticates as: `github-actions[bot]` by default, or `<app-slug>[bot]` when you pass a GitHub App installation token minted in your workflow. Setup, permissions and token-lifetime notes: [Posting as a GitHub App](docs/github-app.md).

## More

- [Triggers](docs/triggers.md): label, review request, non-write actors
- [Configuration reference](docs/configuration.md): all inputs, outputs, env vars
- [How it works](docs/how-it-works.md): review flow, tool allowlist, MemCan preflight
- [GitHub App](docs/github-app.md)
- [Learn action](docs/learn.md): extract review learnings into MemCan after merge

---

Built by [Claudius the Magnificent](https://github.com/lklimek/claudius)
