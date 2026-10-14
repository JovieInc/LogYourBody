#!/usr/bin/env bash
# Reports post-merge Launch Quality for main (ios-post-merge-quality.yml "Report").
#
# Env: QUALITY_RESULT, RETRY_RESULT (job results), HEAD_SHA, RUN_URL, GITHUB_REPOSITORY, GH_TOKEN.
# Passed (first attempt or retry): close every open post-merge-lq-red issue. Failed twice: open
# the issue, or comment on the open one, and exit 1. Anything else (a cancelled or skipped
# attempt) is unknown: no issue change, exit 1, so this SHA is not recorded as verified.
# The open issue is the hold: while it exists, iOS merge groups run Launch Quality again.
set -uo pipefail

label='post-merge-lq-red'
repo="$GITHUB_REPOSITORY"
short="${HEAD_SHA:0:12}"

open_issues() {
  gh api "repos/$repo/issues?labels=$label&state=open&per_page=20" --jq '.[].number'
}

if [[ "$QUALITY_RESULT" == 'success' || "${RETRY_RESULT:-}" == 'success' ]]; then
  if ! issues=$(open_issues); then
    echo '::warning::Could not list post-merge-lq-red issues; leaving the hold as it is.'
    exit 0
  fi
  for issue in $issues; do
    gh api -X POST "repos/$repo/issues/$issue/comments" \
      -f body="Launch Quality passed on main at \`$short\` ($RUN_URL). Closing; iOS merge groups are released from the hold." >/dev/null &&
      gh api -X PATCH "repos/$repo/issues/$issue" -f state=closed -f state_reason=completed >/dev/null &&
      echo "Closed #$issue"
  done
  echo "Launch Quality passed on $short."
  exit 0
fi

if [[ "$QUALITY_RESULT" != 'failure' || "${RETRY_RESULT:-}" != 'failure' ]]; then
  echo "::warning::Launch Quality result unknown (first=$QUALITY_RESULT retry=${RETRY_RESULT:-none}); not recording $short as verified."
  exit 1
fi

if ! issues=$(open_issues); then
  echo '::error::Launch Quality failed twice and the post-merge-lq-red issue could not be listed.'
  exit 1
fi
issue=$(printf '%s\n' "$issues" | head -n 1)
if [[ -n "$issue" ]]; then
  gh api -X POST "repos/$repo/issues/$issue/comments" \
    -f body="Launch Quality failed again on main at \`$short\` after one retry: $RUN_URL" >/dev/null || true
  echo "::error::Launch Quality failed twice on $short; updated #$issue."
else
  gh label create "$label" --repo "$repo" --color B60205 \
    --description 'Post-merge Launch Quality is red on main; iOS merge groups run Launch Quality' >/dev/null 2>&1 || true
  gh api -X POST "repos/$repo/issues" \
    -f title='Post-merge Launch Quality is red on main' \
    -f "labels[]=$label" \
    -f body="Launch Quality failed twice (first attempt and one retry) on main at \`$short\`: $RUN_URL

While this issue is open, iOS merge groups run Launch Quality again, so only a change that passes it can land. The next main SHA that passes closes this issue and releases the hold." >/dev/null || true
  echo "::error::Launch Quality failed twice on $short; opened a post-merge-lq-red issue."
fi
exit 1
