#!/usr/bin/env bash
# Add a heart reaction to the review comments the learn agent saved learnings
# from. Only comments present in the gathered data file whose author is a repo
# owner/member/collaborator are eligible; at most 5 (the per-PR learning cap).
#
# Usage: add-heart-reactions.sh <owner/repo> <data_file>
#
# Requires: gh (authenticated), jq
# Environment: GH_TOKEN; STRUCTURED_OUTPUT — the agent's structured output,
#   {"heart_comment_ids": [<comment_id>, ...]}. Empty or malformed is a no-op.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <owner/repo> <data_file>" >&2
  exit 1
fi

owner_repo="$1"
data_file="$2"

if ! [[ "$owner_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "Error: invalid owner/repo format (expected: owner/repo)" >&2
  exit 1
fi

ids=$(jq -r --slurpfile data "$data_file" '
  ([$data[0].threads[] | .reviewer_comment, .responses[]
    | select(.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
    | .comment_id]) as $eligible
  | [(.heart_comment_ids // [])[] | select(type == "number" and . == floor)]
  | reduce .[] as $id ([]; if any(.[]; . == $id) then . else . + [$id] end)
  | map(select(. as $id | any($eligible[]; . == $id)))
  | .[:5][]' <<<"${STRUCTURED_OUTPUT:-}" 2>/dev/null) || ids=""

count=0
for id in $ids; do
  if gh api "repos/${owner_repo}/pulls/comments/${id}/reactions" -f content=heart --silent; then
    count=$((count + 1))
  else
    echo "::warning::Could not add a heart reaction to review comment ${id}."
  fi
done
echo "Added ${count} heart reaction(s)."
