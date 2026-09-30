# Triggering reviews

## Label (default)

See [`examples/minimal.yml`](../examples/minimal.yml): the review runs when `trigger_label` is applied and on every push while the label stays.

## Triggering by non-write actors

By default, only actors with `admin` or `write` repo access can trigger a
review (add/re-add the trigger label, or push to an already-labeled PR). This
is enforced twice: a fast preflight in this action, and again inside
`claude-code-action` itself — both exist because the underlying action's own
rejection is an opaque error surfacing ~40s into setup.

If a bot or service account with only `triage` permission (e.g. one that
applies the trigger label on your behalf) needs to trigger reviews, add it to
`allowed_non_write_users`:

```yaml
with:
  allowed_non_write_users: my-triage-bot
```

Use a comma-separated list for multiple accounts, or `*` to allow any actor
(not recommended on public repos — see the input's description in
[`action.yml`](../action.yml) for the security caveat).

## Triggering by review request

Instead of a label, you can trigger a review by requesting the bot account
as a PR reviewer:

```yaml
name: Claudius Review
on:
  pull_request:
    types: [review_requested, synchronize]

jobs:
  review:
    if: >
      github.event.pull_request.draft == false &&
      (
        (github.event.action == 'review_requested' && github.event.requested_reviewer.login == 'Claudius-Maginificent') ||
        (github.event.action == 'synchronize' && contains(github.event.pull_request.requested_reviewers.*.login, 'Claudius-Maginificent'))
      )
    # Job-level, so events skipped by `if:` (e.g. an unrelated label) never
    # cancel a running review; a new push to a reviewed PR supersedes it.
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
      cancel-in-progress: true
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      issues: write
      pull-requests: write
    steps:
      - uses: lklimek/claudius-review-action@v3
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          remove_label_on_success: false
          reviewer_login: Claudius-Maginificent
```

`review_requested` fires the moment the account is requested as a reviewer;
the `synchronize` branch re-triggers on new pushes as long as that request is
still pending. Set `remove_label_on_success: false` since there's no trigger
label in this mode — but set `reviewer_login` to the same account named in
the `if:` condition above, or the pending request never clears: the review
itself is posted under whichever GitHub identity `github_token` authenticates
as, not under `reviewer_login`, so GitHub does **not** auto-clear that
account's own pending review request the way it would if it had reviewed
itself. Without `reviewer_login` set, the request stays forever and every
subsequent push re-triggers a full review. To get a fresh review later, just
re-request the review; that fires a new `review_requested` event instead of
re-applying a label.

Requires the reviewer account to be an actual collaborator (not just
implicit public-repo read access) with at least `read`/`triage` permission —
otherwise it won't show up in GitHub's reviewer picker at all.

This mode is still gated by the same write-access preflight described in
["Triggering by non-write actors"](#triggering-by-non-write-actors) above —
it checks `github.event.sender.login` (whoever requested the review, or
pushed on `synchronize`), not the reviewer being requested. If that person
or bot doesn't have `write`/`admin` access, add them to
`allowed_non_write_users` the same way you would for the label trigger.
