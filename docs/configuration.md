# Configuration reference

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | No | `""` | Anthropic API key (alternative to OAuth) |
| `claude_code_oauth_token` | No | `""` | Claude Code OAuth token (alternative to API key) |
| `memcan_url` | No | `""` | MemCan server URL (e.g., `https://memcan.example.com`) |
| `memcan_api_key` | No | `""` | MemCan API key for server authentication |
| `github_token` | No | `${{ github.token }}` | GitHub token for API/CLI; the review is posted as this identity (see [Posting as a GitHub App](github-app.md)) |
| `allowed_non_write_users` | No | `""` | Comma-separated usernames (or `*`) allowed to trigger the review without write/admin access — e.g. a triage-permission bot that only applies the trigger label. Passed through to `claude-code-action`; requires `github_token` |
| `claude_agent` | No | `claudius-ci-reviewer` | Main-thread agent. The default is the lightweight coordinator shipped in [`claude/agents`](../claude/agents); a plugin agent (e.g. `claudius:claudius`) uses its own frontmatter model instead of `model` |
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
| `allowed_tools` | No | *(see action.yml)* | Tool allowlist for Claude. The default covers the review flow; MemCan write tools are always denied |
| `claude_extra_args` | No | `""` | Additional Claude Code CLI flags (appended to built-in args) |
| `report_retention_days` | No | `14` | Artifact retention days |
| `upload_transcripts` | No | `false` | Upload Claude Code session transcripts (coordinator + sub-agents, plus the execution log) as a GPG-encrypted artifact. Requires `transcripts_recipients` — the action fails instead of uploading plaintext |
| `transcript_retention_days` | No | `7` | Retention days for the transcripts artifact |
| `transcripts_recipients` | No | `""` | Newline-separated GPG public keys to encrypt transcripts to: `github:<login>` (keys from `github.com/<login>.gpg`), an `https://` URL to an armored key, or a fingerprint (from keys.openpgp.org). Full 40-hex fingerprints only. Public keys only — no secret needed. Decrypt: `gpg -d claude-transcripts.tar.gz.gpg \| tar xz` |
| `debug_output` | No | `false` | Show full raw Claude Code JSON output in the job log. Also turns on automatically when GitHub's "Enable debug logging" re-run checkbox is checked. **WARNING: may leak secrets/tokens into publicly-visible Actions logs — enable only for troubleshooting**, and be aware that checkbox trips the same warning |

At least one of `anthropic_api_key` or `claude_code_oauth_token` must be provided.

## Claude Code environment variables

Claude Code behavior (effort, turns, etc.) is controlled via environment variables set at the **workflow level** — except the coordinator model, which is the `model` input . The action's pre-flight step logs all recognized variables — check the "Claude Code environment" group in the workflow output for the effective configuration.

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
