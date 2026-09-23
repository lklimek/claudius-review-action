# CLAUDE.md

Guidance for Claude Code working in this repository.

## Project Overview

**claudius-review-action** — a reusable GitHub composite action that wraps [`anthropics/claude-code-action@v1`](https://github.com/anthropics/claude-code-action) to run AI-powered PR code reviews using the Claudius plugin pipeline. GPL-3.0.

Published at: `lklimek/claudius-review-action`

## Repository Structure

```
action.yml              # Main composite action (PR review)
claude/
  skills/ci-pr-review/  # Review flow instructions (installed into ~/.claude/skills)
  agents/               # Coordinator agent (installed into ~/.claude/agents; __MODEL__ templated)
.github/workflows/
  claudius-review.yml   # Self-review of every non-draft PR using `uses: ./`
learn/
  action.yml            # Post-merge learning extraction (WIP — do not touch without asking)
  shared/
    gather-review-data.sh
examples/
  minimal.yml           # Minimal workflow
  extended.yml          # Extended workflow with all options
  review-request.yml    # Trigger via review request instead of a label
  combined.yml          # Review + learn in one file
  learn.yml             # Standalone learn workflow
README.md
```

## Review Flow

The flow lives in the `ci-pr-review` skill (`claude/skills/ci-pr-review/SKILL.md`); the prompt in `action.yml` only invokes it. Keep flow instructions in the skill, not the prompt.

1. `claudius:check-pr-comments` — check and resolve previous review threads
2. `claudius:grumpy-review` — sequential, static-only specialist agents (no builds/tests/reproduction), consolidated report always written (empty is valid)
3. Post MEDIUM+ findings as inline PR comments via `gh api`
4. Approve PR if no unresolved issues remain

Steps 1 and 2 MUST use the `Skill` tool — never perform their work manually. GitHub access is `gh` CLI only (claudius no longer ships a GitHub MCP server).

## Optimization Criteria

When improving this action's performance, apply these criteria in priority order. "Without losing review quality" is a hard constraint across all three.

1. **Decrease number of rounds** (highest priority) — minimize conversation turns between Claude and tools. Prefer skills/agents that batch their own operations over multiple sequential tool calls from the orchestrator.
2. **Decrease running time** (second priority) — reduce wall-clock time of the GitHub Actions job. Avoid redundant checkouts or API calls. Reviewer agents run sequentially by design (see Review Flow) — do not parallelize them.
3. **Decrease number of tokens** (third priority) — reduce token consumption. Trim prompt verbosity, avoid passing large context that is not needed, prefer targeted `gh` calls over broad reads.

## Conventions

- Composite action (YAML only — no JavaScript, no Docker)
- `anthropics/claude-code-action@v1` is the execution engine; this repo only provides the prompt, inputs, and pre/post steps
- Plugin-based architecture: claudius, claudash, memcan — loaded via `plugins` input
- Auth: dual-mode — either `anthropic_api_key` or `claude_code_oauth_token` must be provided
- Claude Code behavior (model, effort, max turns) is controlled via env vars set in the caller's workflow, not in this action
- `learn/` is WIP — the interface is unstable, do not treat it as production-ready

## Development

Test the action by referencing it from a workflow in another repo:

```yaml
- uses: lklimek/claudius-review-action@feat/my-branch
```

Or reference a local path with `act` for local runner testing.

Validate YAML syntax before pushing:

```bash
yamllint action.yml learn/action.yml
```

There is no plugin manifest or CI pipeline in this repo. Changes take effect when the action ref is updated in caller workflows.

## Versioning

Tag releases as `vX.Y.Z` following [SemVer 2](https://semver.org/). The `learn` sub-action is versioned together with the root action.

- **Major**: breaking input/output changes, removed inputs, changed review flow behavior
- **Minor**: new inputs (with defaults), new post-processing steps, new features
- **Patch**: bug fixes, prompt tweaks, doc corrections
