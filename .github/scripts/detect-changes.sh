#!/usr/bin/env bash
# Selects the CI surfaces one change touches (ci.yml "Detect Changes").
#
# Env: BASE_SHA, HEAD_SHA, GITHUB_EVENT_NAME, GITHUB_OUTPUT, plus GITHUB_REPOSITORY and
# GH_TOKEN for the post-merge push dedupe. Writes web, ios_changed and ios.
#
# A merge group's base is the previous group's head, which a shallow main checkout does not
# contain. Diffing against origin/main instead would inherit every queued PR ahead of this one,
# so a web-only group behind an iOS PR would run the full iOS lane. Both commits are fetched by
# SHA and their trees compared directly. When either commit cannot be fetched, every surface is
# selected: an unknown diff never skips a required lane.
set -euo pipefail

web_pattern='^(agent/|evals/|apps/web/|packages/|\.github/actions/|\.github/scripts/|\.github/workflows/|package\.json$|pnpm-lock\.yaml$|pnpm-workspace\.yaml$|scripts/|turbo\.json$)'
# Everything the iOS and iOS Launch Quality Gate jobs read: the app, its scripts, the setup
# actions, the Mac routing that runs them, and the workflows that call them. Root package.json
# and the JS workspace are not inputs: those jobs run xcodebuild, fastlane and python only.
ios_pattern='^(apps/ios/|scripts/ios/|\.github/actions/(setup-ios-build|setup-ruby-bundler)/|\.github/scripts/(mac-lane\.sh|detect-changes\.sh)$|\.github/workflows/(ci|mac-lane|mac-lane-route)\.yml$|\.github/workflows/ios[^/]*\.yml$)'

have_commit() { git cat-file -e "$1^{commit}" 2>/dev/null; }

ensure_commit() {
  have_commit "$1" || git fetch --quiet --no-tags --depth=1 origin "$1" 2>/dev/null || true
  have_commit "$1"
}

changed_files=''
diff_known=false
if [[ -n "${BASE_SHA:-}" && ! "$BASE_SHA" =~ ^0+$ && -n "${HEAD_SHA:-}" ]] &&
  ensure_commit "$BASE_SHA" && ensure_commit "$HEAD_SHA"; then
  changed_files=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")
  diff_known=true
else
  echo "::warning::Could not diff '${BASE_SHA:-}'..'${HEAD_SHA:-}'; selecting every surface."
fi

matches() { [[ "$diff_known" == 'false' ]] || printf '%s\n' "$changed_files" | grep -Eq "$1"; }

web=false
matches "$web_pattern" && web=true
echo "web=$web" >> "$GITHUB_OUTPUT"

ios_changed=false
matches "$ios_pattern" && ios_changed=true
echo "ios_changed=$ios_changed" >> "$GITHUB_OUTPUT"

# macOS capacity is the scarce shared resource, so iOS verification runs once:
# in the merge group, which tests the exact tree that lands on main/production.
# PR runs skip it (the queue re-verifies). The post-merge main push skips it when
# the merge group for this exact SHA passed CI Summary: that group selected iOS from
# its own diff, and under ALLGREEN every earlier group in the batch passed too, so
# the last group that changed an iOS input already ran both iOS jobs on that input.
# (Reusable-workflow job names are "iOS / Unit", never plain "iOS".)
run_ios="$ios_changed"
if [[ "$ios_changed" == 'true' && "$GITHUB_EVENT_NAME" == 'pull_request' ]]; then
  run_ios=false
  echo '::notice::iOS changed; iOS jobs run in the merge group, not on the PR.'
elif [[ "$ios_changed" == 'true' && "$GITHUB_EVENT_NAME" == 'push' ]]; then
  verified_runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$HEAD_SHA&event=merge_group" \
    --jq '.workflow_runs[].id' 2>/dev/null || true)
  for run_id in $verified_runs; do
    passed=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/jobs?per_page=100" \
      --jq '[.jobs[] | select(.name == "CI Summary" and .conclusion == "success")] | length' \
      2>/dev/null || echo 0)
    if [[ "$passed" == '1' ]]; then
      run_ios=false
      echo "::notice::iOS already verified on $HEAD_SHA by merge-group CI run $run_id."
      break
    fi
  done
fi
echo "ios=$run_ios" >> "$GITHUB_OUTPUT"
