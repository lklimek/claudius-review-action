# How it works

The action installs a small `ci-pr-review` skill and `claudius-ci-reviewer`
agent (from [`claude/`](../claude)) into the runner's `~/.claude`, then asks
Claude to run that skill. The skill:

1. runs `claudius:check-pr-comments` — replies to and resolves threads that
   are already fixed;
2. runs `claudius:grumpy-review` with CI overrides — reviewers run **in
   parallel**, do **static review only** (no builds, tests or
   reproduction attempts; unconfirmed findings are reported, not dropped),
   and a report is **always** written, even when nothing was found;
3. posts the review with claudius's `post_pr_review.py`, which maps findings
   onto the diff, skips ones already raised in open threads and approves the
   PR when nothing is left unresolved.

Requires **claudius ≥ 8.2.0** (installed from the marketplace at run time).
All GitHub access goes through the `gh` CLI (no GitHub MCP server).

**Permissions.** The default `allowed_tools` holds only what the flow needs:
file tools, read-only `git` and `gh pr` commands, the claudius plugin scripts
and MemCan search. `gh api`, `env`, `curl` and shells are not on it. This
raises the bar for prompt injection via PR content but is not a sandbox: file
tools are not confined to the workspace, so only run reviews on PRs from
authors you trust with the job's secrets.

**MemCan preflight.** When `memcan_url`/`memcan_api_key` are set, the action
probes `/health` and an MCP `initialize` (status codes only, session closed
afterwards) and continues without MemCan if the server isn't usable. It warns
when the URL is plain HTTP to a non-local host. MemCan is search-only in CI:
write tools are always denied, since PR content is untrusted.

**Posted-review detection.** After the review, the action looks for the review
it posted: on the head commit, submitted during this run, not by the PR
author, containing claudius's attribution footer, and authored by a bot or a
repo collaborator/org member (`author_association` OWNER/MEMBER/COLLABORATOR).
The last check stops an outsider pasting the footer from counting. A machine
user posting via `github_token` must therefore be a repository collaborator
(any role, e.g. triage) or org member — otherwise the job fails with "no
Claudius review was posted" even though the review is visible. The report
link is appended to the newest matching review.

This repository reviews its own non-draft PRs with the PR's version of the
action — see [`.github/workflows/claudius-review.yml`](../.github/workflows/claudius-review.yml).
