#!/usr/bin/env bash
# Selects the CI surfaces one change touches (ci.yml "Detect Changes").
#
# Env: BASE_SHA, HEAD_SHA, GITHUB_EVENT_NAME, GITHUB_OUTPUT, plus GITHUB_REPOSITORY and
# GH_TOKEN for the push dedupe and the merge-group hold check, PR_DRAFT on pull requests.
# Writes web, ios_changed, ios_unit, ios_quality and ios_quality_deferred.
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

# macOS capacity is the scarce shared resource, so each iOS job runs once, where it is cheapest
# and still gates the merge (Unit p50 17 min, Launch Quality p50 28 min, one hosted runner each):
# - pull_request: Launch Quality on the PR head, once the PR is ready for review. A draft
#   defers it; ci.yml reruns on ready_for_review, and that newer CI Summary is the one the
#   queue reads. Unit waits for the merge group.
# - merge_group: Unit only, on the exact tree that lands. While main's post-merge Launch
#   Quality is red (an open post-merge-lq-red issue) Launch Quality runs here too, so only a
#   change that passes it lands until main is green. An unknown hold state counts as held.
# - push (main): Unit only when no passing merge group verified this exact SHA; under ALLGREEN
#   the last group that changed an iOS input already ran Unit on it. Launch Quality for main
#   runs in ios-post-merge-quality.yml.
# - anything else: both jobs.
# (Reusable-workflow job names are "iOS / Unit", never plain "iOS".)
ios_unit=false
ios_quality=false
ios_quality_deferred=false
if [[ "$ios_changed" == 'true' ]]; then
  case "$GITHUB_EVENT_NAME" in
    pull_request)
      if [[ "${PR_DRAFT:-false}" == 'true' ]]; then
        ios_quality_deferred=true
        echo '::notice::iOS changed on a draft; Launch Quality runs when the PR is ready for review.'
      else
        ios_quality=true
      fi
      ;;
    merge_group)
      ios_unit=true
      if ! held=$(gh api "repos/$GITHUB_REPOSITORY/issues?labels=post-merge-lq-red&state=open&per_page=1" \
        --jq 'length' 2>/dev/null); then
        held=unknown
      fi
      if [[ "$held" != '0' ]]; then
        ios_quality=true
        echo "::notice::Post-merge Launch Quality hold is on (open issues: $held); this group runs Launch Quality."
      fi
      ;;
    push)
      ios_unit=true
      verified_runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$HEAD_SHA&event=merge_group" \
        --jq '.workflow_runs[].id' 2>/dev/null || true)
      for run_id in $verified_runs; do
        passed=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/jobs?per_page=100" \
          --jq '[.jobs[] | select(.name == "CI Summary" and .conclusion == "success")] | length' \
          2>/dev/null || echo 0)
        if [[ "$passed" == '1' ]]; then
          ios_unit=false
          echo "::notice::iOS Unit already verified on $HEAD_SHA by merge-group CI run $run_id."
          break
        fi
      done
      ;;
    *)
      ios_unit=true
      ios_quality=true
      ;;
  esac
fi
{
  echo "ios_unit=$ios_unit"
  echo "ios_quality=$ios_quality"
  echo "ios_quality_deferred=$ios_quality_deferred"
} >> "$GITHUB_OUTPUT"
