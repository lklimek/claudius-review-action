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

# Claudius reviews: a claudius marker in the body (attribution footer from
# post_pr_review.py >= 8.2.0, or this action's report-link line) AND an origin
# an outsider cannot forge — a bot (only installed Apps / Actions can post as
# one) or a repo owner/member/collaborator. Covers any github_token identity.
echo "Fetching Claudius reviews..."
reviews_json=$(gh api --paginate "repos/${owner}/${repo}/pulls/${pr_number}/reviews" \
  --jq '.[] | select(((.body // "") | contains("Co-authored by [Claudius the Magnificent](https://github.com/lklimek/claudius)")
      or test("(^|\n)📊 \\*\\*\\[View full HTML review report\\]\\("))
    and (.user.type == "Bot" or (.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))))
    | {id, user: .user.login}' \
  | jq -s '.')

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

# Process threads into the target structure using jq
echo "Processing thread data..."
processed_threads=$(echo "$threads_json" | jq --argjson max_len "$MAX_BODY_LENGTH" \
  --argjson ids "$(echo "$reviews_json" | jq '[.[].id]')" '
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
        )
      }
    end
  )
')

# Calculate stats
echo "Calculating stats..."
# GraphQL logins drop the "[bot]" suffix the REST reviews API returns.
stats=$(echo "$processed_threads" | jq --argjson reviews "$reviews_json" '
  ($reviews | map(.user | sub("\\[bot\\]$"; ""))) as $claudius_logins |
  {
    total_threads: length,
    resolved: [.[] | select(.resolved == true)] | length,
    unresolved: [.[] | select(.resolved == false)] | length,
    claudius_reviews: ($reviews | length),
    claudius_threads: [.[] | select(.claudius)] | length,
    human_responses: [.[] | select(.claudius) | .responses[]
      | select((.bot | not) and (.user as $u | $claudius_logins | index($u) | not))] | length
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
echo "Gathered ${thread_count} threads (${claudius_count} from Claudius, ${human_count} human responses)"
echo "Output written to: ${output_file}"
