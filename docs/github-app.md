# GitHub App setup

The action does all GitHub work (reading the PR, posting the review, replying
to threads, removing the trigger label or review request) with the token passed
as `github_token`. That token is a GitHub App installation token minted in the
**calling** workflow, so the review is posted as `<app-slug>[bot]` with a
short-lived, repository-scoped token.

## Creating the App

Create the App under **Settings → Developer settings → GitHub Apps** of your
user or organization:

| Setting | Value | Why |
|---------|-------|-----|
| Webhook | inactive | the action is driven by workflow events, not webhooks |
| Contents | Read-only | read repository contents; no push access |
| Issues | Read and write | remove the trigger label, fallback PR comment |
| Pull requests | Read and write | post reviews, reply to threads, clear review requests |
| Metadata | Read-only | implicit |

Generate a private key, then **Install App** on each repository to review.
Store the Client ID as the Actions variable `REVIEW_APP_CLIENT_ID` and the
full `.pem` contents as the Actions secret `REVIEW_APP_PRIVATE_KEY` (repository
or organization level).

## Minting the token

```yaml
permissions:
  contents: read  # checkout only
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
  - uses: lklimek/claudius-review-action@v1
    with:
      claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      github_token: ${{ steps.app-token.outputs.token }}
```

`repositories` and the `permission-*` inputs narrow the token to this
repository and to what the review needs, even if the App is installed more
widely or granted more. The job's `GITHUB_TOKEN` is used only by the action's
own checkout, hence `contents: read`; with `checkout: false`, your checkout
step needs the same. The [learn job](learn.md) mints its own token the same
way, with `permission-pull-requests: write` only.

## Failure modes

There is deliberately no fallback to `GITHUB_TOKEN`: a missing or misconfigured
App fails the job loudly instead of quietly running under a different identity
with different permissions.

- **Token step fails** (variable or secret unset, App not installed on the
  repository, a requested permission not granted to the App): the job stops at
  that step and the review never starts.
- **Empty or missing `github_token`**: the input is required and has no
  default. An explicitly passed input always wins, even when it evaluates to an
  empty string — e.g. it references a step that was skipped by an `if:`,
  removed, or misspelled (step id or output name). The action's first step
  then fails with "github_token is empty"; check the step id and
  `outputs.token` spelling.

Do not paper over this with `|| github.token`: the job token has only
`contents: read`, so it cannot post a review anyway, and widening the job's
`permissions:` to make it work reintroduces a second, broader identity that
the App exists to replace.

## Operational notes

- **Key handling.** The action takes a token, not the App's private key: the
  key can mint tokens for every installation of the App until rotated. Pass it
  only in the token step's `with:`, never in job- or workflow-level `env:`,
  which the Claude session's step inherits.
- **Token lifetime.** Installation tokens expire 1 hour after minting (and
  `create-github-app-token` revokes them when the job ends). Mint the token in
  the job's first step and keep `timeout-minutes` at 60 or less, so the job
  always ends before the token does.
- **Resolving threads** (`resolveReviewThread`) requires **Contents: Read and
  write**, so it is refused for a read-only App. The review then lists
  fixed-but-unresolved threads in its body instead; granting Contents write to
  fix this also grants push.
- **Workflow triggers.** App-token activity triggers other workflows: the
  review and report-link edit fire `pull_request_review`, thread replies
  `pull_request_review_comment`, thread resolution
  `pull_request_review_thread`, the fallback comment `issue_comment`, and label
  or review-request removal `pull_request` (`unlabeled`,
  `review_request_removed`).
- **Posted-review detection.** The action and the learn job recognize the
  review by its attribution footer and a bot author, which an App always is
  (see [How it works](how-it-works.md)).
