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
      github_token: ${{ steps.app-token.outputs.token }}
```

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
  other workflows: the review fires `pull_request_review`, the report link
  edit `pull_request_review` (`edited`), the fallback comment `issue_comment`
  and label removal `pull_request` (`unlabeled`).
