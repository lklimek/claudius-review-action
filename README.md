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
      ANTHROPIC_MODEL: sonnet
      CLAUDE_CODE_MAX_TURNS: "200"
      CLAUDE_CODE_EFFORT_LEVEL: high
    steps:
      - uses: lklimek/claudius-review-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
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

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | No | `""` | MemCan server URL (e.g., `http://host:8190`) |
| `memcan_api_key` | No | `""` | MemCan API key for server authentication |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI |
| `claude_agent` | No | `claudius:claudius` | Claude agent persona |
| `plugins` | No | `claudius@lklimek`, `claudash@lklimek`, `memcan@lklimek` | Newline-separated plugin list |
| `plugin_marketplaces` | No | `https://github.com/lklimek/agents.git` | Newline-separated marketplace URLs |
| `prompt_extra` | No | `""` | Additional instructions appended to core prompt |
| `trigger_label` | No | `claudius-review` | Label to remove on success |
| `remove_label_on_success` | No | `true` | Whether to remove trigger label |
| `checkout` | No | `true` | Whether action handles git checkout |
| `fetch_depth` | No | `0` | Git fetch depth (only if checkout=true) |
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags (appended to built-in args) |
| `report_retention_days` | No | `14` | Artifact retention days |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

## Claude Code Environment Variables

Claude Code behavior (model, effort, turns, etc.) is controlled via environment variables set at the **workflow level**. The action's pre-flight step logs all recognized variables — check the "Claude Code environment" group in the workflow output for the effective configuration.

Set them in your workflow's `env:` block:

```yaml
jobs:
  review:
    env:
      ANTHROPIC_MODEL: opus
      CLAUDE_CODE_MAX_TURNS: "150"
      CLAUDE_CODE_EFFORT_LEVEL: high
      CLAUDE_CODE_SUBAGENT_MODEL: sonnet
```

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

## Learn Action

The **Claudius Learn** action (`lklimek/claudius-review-action/learn@v1`) extracts reusable learnings from completed PR code reviews and saves them to MemCan. It runs after a PR merges, analyzes how developers responded to review findings (accepted, rejected, or ignored), and stores project-specific patterns so future reviews improve over time.

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
      pull-requests: read
    env:
      ANTHROPIC_MODEL: sonnet
    steps:
      - uses: lklimek/claudius-review-action/learn@v1
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
- Only `contents: read` and `pull-requests: read` permissions are needed

### Cost

The learn action exits early (zero cost) when preconditions are not met (no claude[bot] reviews, not merged, below comment threshold). When it does run, Sonnet or Haiku is recommended -- expect approximately $0.02-0.06 per invocation depending on PR size.

---

Built by [Claudius the Magnificent](https://github.com/lklimek/claudius)
