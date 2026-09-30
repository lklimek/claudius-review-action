# Posting as a GitHub App

By default the review is posted as `github-actions[bot]` (`GITHUB_TOKEN`). To
post under your own GitHub App identity (`<app-slug>[bot]`), mint a
short-lived installation token in the **caller** workflow and pass it as
`github_token`:

```yaml
steps:
  - uses: actions/create-github-app-token@v3
    id: app-token
    with:
      client-id: ${{ vars.REVIEW_APP_CLIENT_ID }}
      private-key: ${{ secrets.REVIEW_APP_PRIVATE_KEY }}
      repositories: ${{ github.event.repository.name }}
      permission-contents: read
      permission-issues: write
      permission-pull-requests: write
  - uses: lklimek/claudius-review-action@v3
    with:
      claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      github_token: ${{ steps.app-token.outputs.token || github.token }}
```

An explicitly passed `github_token` always overrides the input's default, even
when it evaluates to an empty string — the action then has no token, it does not
fall back to `GITHUB_TOKEN`. That happens whenever the token step is skipped or
removed (or its output is misspelled) while `github_token` still references it.
The `|| github.token` fallback above keeps the review running as
`github-actions[bot]` in that case — with the job's `permissions:` rather than
the App token's narrower scope, so keep those least-privilege too. The action
logs which identity posted the review. Drop the `github_token` line entirely to
go back to the default identity.

App setup: repository permissions **Contents: Read-only** (no push),
**Issues: Read & write**, **Pull requests: Read & write** (Metadata: Read is
implicit); webhook disabled; installed on the target repository. The job's
`permissions:` still apply — the checkout uses `GITHUB_TOKEN`.

- **Key handling.** The action deliberately takes a token, not the App's
  private key: the key can mint tokens for every installation of the App until
  rotated. Pass it only in the token step's `with:` — never in job- or
  workflow-level `env:`, which the Claude session's step inherits.
- **Token lifetime.** Installation tokens expire 1 hour after minting (and
  `create-github-app-token` revokes them when the job ends). Mint the token in
  the job's first step and keep `timeout-minutes` at 60 or less, so the job
  always ends before the token does.
- **Resolving threads** (`resolveReviewThread`) requires **Contents: Read &
  write** — it is refused for a read-only App, exactly as for a read-only
  `GITHUB_TOKEN`. The review then lists fixed-but-unresolved threads in its
  body instead; granting Contents write to fix this also grants push.
- **Workflow triggers.** Unlike `GITHUB_TOKEN`, App-token activity triggers
  other workflows: the review and report-link edit fire `pull_request_review`,
  thread replies `pull_request_review_comment`, thread resolution
  `pull_request_review_thread`, the fallback comment `issue_comment`, and
  label or review-request removal `pull_request` (`unlabeled`,
  `review_request_removed`).
