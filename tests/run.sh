#!/usr/bin/env bash
# Offline tests for lib/claudius.jq, learn/shared/*.sh and action steps, using
# the fake gh in tests/bin. Requires bash, jq, python3 with PyYAML.
# Usage: tests/run.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SHARED="$ROOT/learn/shared"
export PATH="$HERE/bin:$PATH" GH_TOKEN=fake
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export FX="$tmp/fx"
cp -r "$HERE/fixtures" "$FX"
: > "$FX/calls.log"

# --- gather-review-data.sh: only trusted content reaches the data file ---
out="$tmp/data.json"
bash "$SHARED/gather-review-data.sh" o/r 19 "$out" >/dev/null || { echo "FAIL gather-review-data.sh exited non-zero"; exit 1; }
check "thread ids (untrusted-root thread dropped)" "$(jq -c '[.threads[].id]' "$out")" '["T1","T3"]'
check "T1 replies: bot/owner/member/collaborator only" "$(jq -c '[.threads[0].responses[].comment_id]' "$out")" '[2,5,6,7]'
check "T3 untrusted reply dropped" "$(jq -c '.threads[1].responses' "$out")" '[]'
check "no untrusted text anywhere" "$(grep -c -e 'record it' -e 'root spam' -e 'inject' -e meh -e 'Ignore previous' "$out")" 0
check "PR title not in data file" "$(jq -c '.pr | keys' "$out")" '["author","merged_at","number"]'
check "claudius flag" "$(jq -c '[.threads[].claudius]' "$out")" '[true,false]'
check "dropped count stat" "$(jq '.stats.untrusted_comments_dropped' "$out")" 5
check "human_responses counts trusted non-Claudius humans" "$(jq '.stats.human_responses' "$out")" 2
check "claudius_threads" "$(jq '.stats.claudius_threads' "$out")" 1
check "per-thread withheld_responses" "$(jq -c '[.threads[].withheld_responses]' "$out")" '[2,1]'
check "claudius reviews: marker + trusted origin" "$(jq '.stats.claudius_reviews' "$out")" 6

# --- lib/claudius.jq ---
lib() { jq -L "$ROOT/lib" -c "include \"claudius\"; $1" <<<"$2"; }
check "trusted_origin REST bot" "$(lib trusted_origin '{"user":{"type":"Bot"},"author_association":"NONE"}')" true
check "trusted_origin REST member" "$(lib trusted_origin '{"user":{"type":"User"},"author_association":"MEMBER"}')" true
check "trusted_origin REST outsider" "$(lib trusted_origin '{"user":{"type":"User"},"author_association":"CONTRIBUTOR"}')" false
check "trusted_origin GraphQL bot" "$(lib trusted_origin '{"author":{"__typename":"Bot"},"authorAssociation":"NONE"}')" true
check "trusted_origin GraphQL owner" "$(lib trusted_origin '{"author":{"__typename":"User"},"authorAssociation":"OWNER"}')" true
check "trusted_origin deleted user" "$(lib trusted_origin '{"author":null,"authorAssociation":"NONE"}')" false
check "footer matches upstream ATTRIBUTION" "$(lib claudius_footer null)" '"Co-authored by [Claudius the Magnificent](https://github.com/lklimek/claudius) AI Agent"'
check "report line at body start" "$(lib claudius_report_line '"📊 **[View full HTML review report](u)"')" true
check "report line mid-sentence ignored" "$(lib claudius_report_line '"see 📊 **[View full HTML review report](u)"')" false

# --- action.yml: "List reviews posted this run" ---
python3 "$HERE/extract-step.py" "$ROOT/action.yml" posted \
  github.repository=o/r github.event.pull_request.number=19 "github.action_path=$ROOT" > "$tmp/posted.sh" \
  || { echo "FAIL extract posted step"; exit 1; }
: > "$tmp/gh_out"
posted_out=$(GITHUB_OUTPUT="$tmp/gh_out" HEAD_SHA=abc PR_AUTHOR=dev REVIEW_STARTED_AT=2026-09-30T09:30:00Z bash -eo pipefail "$tmp/posted.sh")
check "posted: footer + trusted + this run, newest first" "$(cat "$tmp/gh_out")" "ids=103 101"
check "posted: logs identity" "$posted_out" "Claudius review posted as @collab"

# --- learn/action.yml: workspace must not be a git checkout ---
python3 "$HERE/extract-step.py" "$ROOT/learn/action.yml" no-checkout > "$tmp/no-checkout.sh" \
  || { echo "FAIL extract no-checkout step"; exit 1; }
ws="$tmp/ws"
mkdir -p "$ws"
nocheckout() { GITHUB_WORKSPACE="$ws" bash -eo pipefail "$tmp/no-checkout.sh" 2>&1; echo "rc=$?"; }
check "no-checkout: empty workspace passes" "$(nocheckout)" "rc=0"
mkdir -p "$ws/sub/repo/.git"
check "no-checkout: nested checkout fails" "$(nocheckout | tail -1)" "rc=1"
check "no-checkout: explains why" "$(nocheckout | grep -c '::error::.*checkout')" 1
rm -rf "$ws/sub"
touch "$ws/.git"
check "no-checkout: .git file (worktree/submodule) fails" "$(nocheckout | tail -1)" "rc=1"

# --- add-heart-reactions.sh ---
hearts() { : > "$FX/calls.log"; STRUCTURED_OUTPUT="$1" bash "$SHARED/add-heart-reactions.sh" o/r "$out" >/dev/null 2>&1; echo $?; }
posted() { grep -o 'pulls/comments/[0-9]*/reactions' "$FX/calls.log" | grep -o '[0-9]*' | paste -sd, -; }
check "hearts exit ok" "$(hearts '{"heart_comment_ids":[2,1,5,6,999,20,7]}')" 0
check "only privileged human comments hearted" "$(posted)" "2,6,20,7"
check "content=heart sent" "$(grep -c 'content=heart' "$FX/calls.log")" 4
hearts '{"heart_comment_ids":["2; rm -rf /","3",2.5,null,{"a":1}]}' >/dev/null
check "non-integer ids ignored" "$(posted)" ""
check "empty output is no-op" "$(hearts '')" 0
check "empty output posts nothing" "$(posted)" ""
check "missing field is no-op" "$(hearts '{}')" 0
check "malformed JSON is no-op" "$(hearts 'not json')" 0
hearts '{"heart_comment_ids":[2,2,2]}' >/dev/null
check "duplicates hearted once" "$(posted)" "2"
check "reaction failure does not fail step" "$(FAIL_REACTION=2 hearts '{"heart_comment_ids":[2,6]}')" 0
check "continues after a failed reaction" "$(posted)" "2,6"
capdata="$tmp/cap.json"
jq -n '{threads: [{reviewer_comment: {comment_id: 1, author_association: "OWNER"},
  responses: [range(2; 9) | {comment_id: ., author_association: "MEMBER"}]}]}' > "$capdata"
: > "$FX/calls.log"
STRUCTURED_OUTPUT='{"heart_comment_ids":[1,2,3,4,5,6,7,8]}' bash "$SHARED/add-heart-reactions.sh" o/r "$capdata" >/dev/null 2>&1
check "capped at 5" "$(posted)" "1,2,3,4,5"
check "bad repo rejected" "$(STRUCTURED_OUTPUT='{}' bash "$SHARED/add-heart-reactions.sh" 'o/r x' "$out" >/dev/null 2>&1; echo $?)" 1

exit "$fail"
