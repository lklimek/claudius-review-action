# Claudius PR Review Action

A reusable GitHub composite action that wraps [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) into a single step for AI-powered PR code reviews. It runs the Claudius review pipeline — checking previous comments, performing a fresh multi-specialist code review, posting inline findings, and optionally approving clean PRs.

## Minimal Usage

```yaml
name: Claudius Review
on:
  pull_request:
    types: [labeled]

permissions:
  contents: read
  issues: write
  pull-requests: write
  id-token: write

jobs:
  review:
    if: github.event.label.name == 'claudius-review'
    runs-on: ubuntu-latest
    steps:
      - uses: lklimek/claudius-review-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Extended Usage

```yaml
name: Claudius Review
on:
  pull_request:
    types: [labeled, synchronize]

permissions:
  contents: read
  issues: write
  pull-requests: write
  id-token: write

jobs:
  review:
    if: |
      github.event.action == 'labeled' && github.event.label.name == 'claudius-review' ||
      github.event.action == 'synchronize' && contains(github.event.pull_request.labels.*.name, 'claudius-review')
    runs-on: ubuntu-latest
    steps:
      - uses: lklimek/claudius-review-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          claude_model: sonnet
          max_turns: 200
          prompt_extra: "Focus especially on security issues and SQL injection vectors."
          plugins: |
            claudius@lklimek
            claudash@lklimek
            my-custom-plugin@my-org
          plugin_marketplaces: |
            https://github.com/lklimek/agents.git
            https://github.com/my-org/agents.git
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI |
| `claude_model` | No | `opus` | Claude model to use |
| `claude_agent` | No | `claudius:claudius` | Claude agent persona |
| `max_turns` | No | `150` | Max conversation turns |
| `plugins` | No | `claudius@lklimek`, `claudash@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `prompt_extra` | No | `""` | Additional instructions appended to core prompt |
| `trigger_label` | No | `claudius-review` | Label to remove on success |
| `remove_label_on_success` | No | `true` | Whether to remove trigger label |
| `checkout` | No | `true` | Whether action handles git checkout |
| `fetch_depth` | No | `0` | Git fetch depth (only if checkout=true) |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude |
| `report_retention_days` | No | `14` | Artifact retention days |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

## Outputs

| Output | Description |
|--------|-------------|
| `report_artifact_name` | Name of the uploaded review report artifact |

## Required Permissions

```yaml
permissions:
  contents: read
  issues: write
  pull-requests: write
  id-token: write
```

---

Built by [Claudius the Magnificent](https://github.com/lklimek/claudius)
