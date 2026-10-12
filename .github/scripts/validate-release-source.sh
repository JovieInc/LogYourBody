#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
SHA="${GITHUB_SHA:?GITHUB_SHA is required}"
REF_NAME="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
EVENT_NAME="${GITHUB_EVENT_NAME:?GITHUB_EVENT_NAME is required}"
RELEASE_TYPE="${RELEASE_TYPE:-testflight}"
REQUIRED_CHECKS="${REQUIRED_CHECKS:-CI Summary,JavaScript/TypeScript,iOS}"
RELEASE_CHECK_TIMEOUT_SECONDS="${RELEASE_CHECK_TIMEOUT_SECONDS:-2700}"
RELEASE_CHECK_POLL_SECONDS="${RELEASE_CHECK_POLL_SECONDS:-15}"

fail() {
  echo "::error::$1" >&2
  exit 1
}

warn() {
  echo "::warning::$1" >&2
}

echo "Validating release source:"
echo "- repository: $REPO"
echo "- ref: $REF_NAME"
echo "- sha: $SHA"
echo "- event: $EVENT_NAME"
echo "- release type: $RELEASE_TYPE"

if [ "$EVENT_NAME" = "push" ] && [ "$REF_NAME" != "main" ]; then
  fail "Push-triggered releases must come from main."
fi

if [ "$RELEASE_TYPE" = "app_store" ] && [ "$REF_NAME" != "main" ]; then
  fail "App Store releases must run from main."
fi

if ! command -v node >/dev/null 2>&1; then
  fail "Node.js is required to validate the App Store storefront."
fi

echo "Validating generated App Store storefront..."
node packages/product-registry/scripts/storefront.test.mjs

STATUS_STATE="$(gh api "repos/$REPO/commits/$SHA/status" --jq '.state')"
case "$STATUS_STATE" in
  success)
    echo "Commit statuses are successful."
    ;;
  failure|error)
    warn "Commit status state for $SHA is $STATUS_STATE; continuing because required check runs are validated explicitly."
    ;;
  pending)
    warn "Commit status state for $SHA is pending; continuing because required check runs are validated separately when present."
    ;;
  *)
    warn "Commit status state for $SHA is $STATUS_STATE."
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_JSON="$(mktemp)"
JOBS_JSON="$(mktemp)"
cleanup() {
  rm -f "$RUNS_JSON" "$JOBS_JSON"
}
trap cleanup EXIT

validate_required_checks_once() {
  gh api "repos/$REPO/actions/workflows/ci.yml/runs?head_sha=$SHA&per_page=100" \
    --paginate --slurp > "$RUNS_JSON" || fail "Unable to read CI workflow runs."
  run_id="$(node "$SCRIPT_DIR/validate-release-checks.mjs" select "$SHA" "$REPO" "$EVENT_NAME" "$RUNS_JSON")" || fail "Invalid CI workflow run metadata."
  printf '[{"jobs":[]}]\n' > "$JOBS_JSON"
  if [ -n "$run_id" ]; then
    gh api "repos/$REPO/actions/runs/$run_id/jobs?filter=latest&per_page=100" \
      --paginate --slurp > "$JOBS_JSON" || fail "Unable to read selected CI jobs."
  fi
  result=0
  node "$SCRIPT_DIR/validate-release-checks.mjs" validate "$SHA" "$REPO" "$EVENT_NAME" "$RUNS_JSON" "$REQUIRED_CHECKS" \
    < "$JOBS_JSON" || result=$?
  case "$result" in
    0) return 0 ;;
    2) return 1 ;;
    *) fail "Required CI run evidence did not pass." ;;
  esac
}

deadline=$((SECONDS + RELEASE_CHECK_TIMEOUT_SECONDS))
while true; do
  if validate_required_checks_once; then
    break
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "Required CI checks did not pass within ${RELEASE_CHECK_TIMEOUT_SECONDS}s on ref $REF_NAME for $SHA."
  fi

  echo "Waiting ${RELEASE_CHECK_POLL_SECONDS}s for required CI checks..."
  sleep "$RELEASE_CHECK_POLL_SECONDS"
done

echo "Release source validation passed."
