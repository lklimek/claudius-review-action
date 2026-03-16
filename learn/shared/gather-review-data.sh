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
  --jq '{number: .number, title: .title, author: .user.login, merged_at: .merged_at}')

# Fetch review threads via GraphQL (includes resolution status and all comments)
echo "Fetching review threads via GraphQL..."
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
                  author { login }
                  authorAssociation
                  body
                  path
                  createdAt
                }
              }
            }
          }
        }
      }
    }')

# Process threads into the target structure using jq
echo "Processing thread data..."
processed_threads=$(echo "$threads_json" | jq --argjson max_len "$MAX_BODY_LENGTH" '
  .data.repository.pullRequest.reviewThreads.nodes
  | map(
    . as $thread |
    ($thread.comments.nodes // []) as $comments |
    if ($comments | length) == 0 then empty
    else
      {
        id: $thread.id,
        file: ($comments[0].path // "unknown"),
        resolved: $thread.isResolved,
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
              body: ((.body // "") | if (. | length) > $max_len then .[0:$max_len] + "..." else . end)
            })
        )
      }
    end
  )
')

# Calculate stats
echo "Calculating stats..."
stats=$(echo "$processed_threads" | jq '
  {
    total_threads: length,
    resolved: [.[] | select(.resolved == true)] | length,
    unresolved: [.[] | select(.resolved == false)] | length,
    claude_threads: [.[] | select(.reviewer_comment.user == "claude[bot]")] | length,
    human_responses: [.[].responses[] | select(.user != "claude[bot]" and .user != "github-actions[bot]")] | length
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
claude_count=$(echo "$stats" | jq '.claude_threads')
human_count=$(echo "$stats" | jq '.human_responses')
echo "Gathered ${thread_count} threads (${claude_count} from claude[bot], ${human_count} human responses)"
echo "Output written to: ${output_file}"
