#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
SHA="${GITHUB_SHA:?GITHUB_SHA is required}"
REF_NAME="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
EVENT_NAME="${GITHUB_EVENT_NAME:?GITHUB_EVENT_NAME is required}"
RELEASE_TYPE="${RELEASE_TYPE:-testflight}"
REQUIRED_CHECKS="${REQUIRED_CHECKS:-CI Summary,JavaScript/TypeScript,iOS}"
RELEASE_CHECK_TIMEOUT_SECONDS="${RELEASE_CHECK_TIMEOUT_SECONDS:-900}"
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

STATUS_STATE="$(gh api "repos/$REPO/commits/$SHA/status" --jq '.state')"
case "$STATUS_STATE" in
  success)
    echo "Commit statuses are successful."
    ;;
  failure|error)
    fail "Commit status state for $SHA is $STATUS_STATE."
    ;;
  pending)
    warn "Commit status state for $SHA is pending; continuing because required check runs are validated separately when present."
    ;;
  *)
    warn "Commit status state for $SHA is $STATUS_STATE."
    ;;
esac

CHECK_RUNS_TSV="$(mktemp)"
cleanup() {
  rm -f "$CHECK_RUNS_TSV"
}
trap cleanup EXIT

IFS=',' read -r -a required_checks <<< "$REQUIRED_CHECKS"

load_check_runs() {
  gh api "repos/$REPO/commits/$SHA/check-runs?per_page=100" \
    --paginate \
    --jq '.check_runs[] | [.name, .status, (.conclusion // ""), (.completed_at // .started_at // ""), (.id | tostring)] | @tsv' \
    > "$CHECK_RUNS_TSV"
}

validate_required_checks_once() {
  found_required=0
  missing_required=()
  pending_required=()

  for check_name in "${required_checks[@]}"; do
    check_name="$(printf '%s' "$check_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$check_name" ] || continue

    matches="$(awk -F '\t' -v wanted="$check_name" '$1 == wanted { print }' "$CHECK_RUNS_TSV" | LC_ALL=C sort -t $'\t' -k4,4)"

    if [ -z "$matches" ]; then
      missing_required+=("$check_name")
      continue
    fi

    found_required=1
    latest="$(printf '%s\n' "$matches" | tail -n 1)"
    status="$(printf '%s' "$latest" | cut -f2)"
    conclusion="$(printf '%s' "$latest" | cut -f3)"

    if [ "$status" != "completed" ]; then
      pending_required+=("$check_name:$status")
      continue
    fi

    if [ "$conclusion" != "success" ] && [ "$conclusion" != "skipped" ]; then
      fail "Required check '$check_name' concluded $conclusion."
    fi

    echo "Required check '$check_name' concluded $conclusion."
  done

  if [ "$found_required" -eq 0 ]; then
    echo "No required CI check runs found yet on ref $REF_NAME for $SHA."
    return 1
  fi

  if [ "${#missing_required[@]}" -gt 0 ]; then
    echo "Required CI checks missing so far: ${missing_required[*]}"
    return 1
  fi

  if [ "${#pending_required[@]}" -gt 0 ]; then
    echo "Required CI checks pending so far: ${pending_required[*]}"
    return 1
  fi

  return 0
}

deadline=$((SECONDS + RELEASE_CHECK_TIMEOUT_SECONDS))
while true; do
  load_check_runs

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
