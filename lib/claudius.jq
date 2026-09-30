# Claudius review identification, shared by the review and learn actions.
# Load with: jq -L <repo>/lib 'include "claudius"; ...'

# Must match ATTRIBUTION in lklimek/claudius scripts/post_pr_review.py (>= 8.2.0),
# which ends every review body it posts; update both together.
def claudius_footer: "Co-authored by [Claudius the Magnificent](https://github.com/lklimek/claudius) AI Agent";

# Report link line the review action adds to the review it posted.
def claudius_report_line: test("(^|\n)📊 \\*\\*\\[View full HTML review report\\]\\(");

def privileged_association: IN("OWNER", "MEMBER", "COLLABORATOR");

# Author an outsider cannot impersonate: a bot (only installed Apps / Actions
# post as one) or a repo owner/member/collaborator. Accepts REST objects
# (.user.type, .author_association) and GraphQL ones (.author.__typename,
# .authorAssociation).
def trusted_origin:
  (.user.type // .author.__typename) == "Bot"
  or ((.author_association // .authorAssociation // "NONE") | privileged_association);
