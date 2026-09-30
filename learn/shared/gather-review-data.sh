#!/usr/bin/env bash
# Gather review interaction data from a pull request and output structured JSON.
#
# Usage: gather-review-data.sh <owner/repo> <pr_number> <output_file>
#
# Requires: gh (authenticated), jq
# Environment: GH_TOKEN must be set
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <owner/repo> <pr_number> <output_file>" >&2
  exit 1
fi

owner_repo="$1"
pr_number="$2"
output_file="$3"

if ! [[ "$owner_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "Error: invalid owner/repo format (expected: owner/repo)" >&2
  exit 1
fi

owner="${owner_repo%/*}"
repo="${owner_repo##*/}"

if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "Error: pr_number must be a positive integer" >&2
  exit 1
fi

if [[ -z "$output_file" ]]; then
  echo "Error: output_file must not be empty" >&2
  exit 1
fi

MAX_BODY_LENGTH=500
lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"

truncate_body() {
  local body="$1"
  if [[ ${#body} -gt $MAX_BODY_LENGTH ]]; then
    echo "${body:0:$MAX_BODY_LENGTH}..."
  else
    echo "$body"
  fi
}

echo "::group::Gathering review data for ${owner_repo}#${pr_number}"

# Fetch PR metadata
echo "Fetching PR metadata..."
pr_json=$(gh api "repos/${owner}/${repo}/pulls/${pr_number}" \
  --jq '{number: .number, author: .user.login, merged_at: .merged_at}')

# Claudius reviews: a claudius marker in the body (attribution footer or this
# action's report-link line) AND a trusted origin (see lib/claudius.jq).
echo "Fetching Claudius reviews..."
reviews_json=$(gh api --paginate "repos/${owner}/${repo}/pulls/${pr_number}/reviews" \
  | jq -s -L "$lib_dir" 'include "claudius";
    add // [] | map(select(((.body // "") | contains(claudius_footer) or claudius_report_line)
      and trusted_origin) | {id, user: .user.login})')

# Fetch review threads via GraphQL (includes resolution status and all comments)
echo "Fetching review threads via GraphQL..."
# $owner etc. in the query are GraphQL variables, not shell expansions.
# shellcheck disable=SC2016
threads_json=$(gh api graphql \
  -F owner="$owner" \
  -F repo="$repo" \
  -F pr_number="$pr_number" \
  -f query='
    query($owner: String!, $repo: String!, $pr_number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr_number) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 50) {
                nodes {
                  databaseId
                  author { login __typename }
                  authorAssociation
                  body
                  path
                  createdAt
                  pullRequestReview { databaseId }
                }
              }
            }
          }
        }
      }
    }')

# Only comments from bots or repo owners/members/collaborators reach the
# memory-writing agent: a thread with an untrusted first comment is dropped
# whole, untrusted replies individually.
echo "Processing thread data..."
thread_nodes=$(echo "$threads_json" | jq '.data.repository.pullRequest.reviewThreads.nodes')
untrusted_dropped=$(echo "$thread_nodes" | jq -L "$lib_dir" 'include "claudius";
  [.[] | (.comments.nodes // []) | if (.[0] | trusted_origin) then map(select(trusted_origin | not)) else . end | length] | add // 0')
processed_threads=$(echo "$thread_nodes" | jq -L "$lib_dir" --argjson max_len "$MAX_BODY_LENGTH" \
  --argjson ids "$(echo "$reviews_json" | jq '[.[].id]')" 'include "claudius";
  map(
    . as $thread |
    ($thread.comments.nodes // []) as $all |
    if ($all | length) == 0 or ($all[0] | trusted_origin | not) then empty
    else ($all | map(select(trusted_origin))) as $comments |
      {
        id: $thread.id,
        file: ($comments[0].path // "unknown"),
        resolved: $thread.isResolved,
        claudius: ($comments[0].pullRequestReview.databaseId as $rid | any($ids[]; . == $rid)),
        reviewer_comment: {
          comment_id: $comments[0].databaseId,
          user: ($comments[0].author.login // "unknown"),
          author_association: ($comments[0].authorAssociation // "NONE"),
          body: (($comments[0].body // "") | if (. | length) > $max_len then .[0:$max_len] + "..." else . end)
        },
        responses: (
          $comments[1:]
          | map({
              comment_id: .databaseId,
              user: (.author.login // "unknown"),
              author_association: (.authorAssociation // "NONE"),
              bot: (.author.__typename == "Bot"),
              body: ((.body // "") | if (. | length) > $max_len then .[0:$max_len] + "..." else . end)
            })
        ),
        withheld_responses: (($all | length) - ($comments | length))
      }
    end
  )
')

# Calculate stats
echo "Calculating stats..."
# GraphQL logins drop the "[bot]" suffix the REST reviews API returns.
stats=$(echo "$processed_threads" | jq --argjson reviews "$reviews_json" \
  --argjson untrusted_dropped "$untrusted_dropped" '
  ($reviews | map(.user | sub("\\[bot\\]$"; ""))) as $claudius_logins |
  {
    total_threads: length,
    resolved: [.[] | select(.resolved == true)] | length,
    unresolved: [.[] | select(.resolved == false)] | length,
    claudius_reviews: ($reviews | length),
    claudius_threads: [.[] | select(.claudius)] | length,
    human_responses: [.[] | select(.claudius) | .responses[]
      | select((.bot | not) and (.user as $u | $claudius_logins | index($u) | not))] | length,
    untrusted_comments_dropped: $untrusted_dropped
  }
')

# Assemble final output
echo "Assembling output..."
jq -n \
  --argjson pr "$pr_json" \
  --argjson threads "$processed_threads" \
  --argjson stats "$stats" \
  '{pr: $pr, threads: $threads, stats: $stats}' > "$output_file"

echo "::endgroup::"

thread_count=$(echo "$stats" | jq '.total_threads')
claudius_count=$(echo "$stats" | jq '.claudius_threads')
human_count=$(echo "$stats" | jq '.human_responses')
echo "Gathered ${thread_count} threads (${claudius_count} from Claudius, ${human_count} human responses; ${untrusted_dropped} untrusted comments dropped)"
echo "Output written to: ${output_file}"
