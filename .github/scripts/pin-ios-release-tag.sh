#!/usr/bin/env bash
# Pin the iOS release tag to the commit this workflow built.
#
# Do this before the long validate/build/TestFlight jobs. Once main moves onto
# a commit with different .github/workflows files, GITHUB_TOKEN cannot create a
# tag or a release at the built SHA (HTTP 403, or "without workflows
# permission"). A scope refusal is a warning so TestFlight still runs. Any
# other pin failure stops the workflow before an untagged build is shipped
# without a clear script error.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PBXPROJ="apps/ios/LogYourBody.xcodeproj/project.pbxproj"

fail() {
  echo "::error::$1" >&2
  exit 1
}

warn() {
  echo "::warning::$1" >&2
}

out() {
  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    fail "GITHUB_OUTPUT is required"
  fi
  printf '%s\n' "$1" >> "$GITHUB_OUTPUT"
}

scope_denied() {
  printf '%s' "$1" | node "$SCRIPT_DIR/ios-release-tag.mjs" scope-denied
}

delete_tag() {
  local tag="${TAG:-}"
  if [[ -z "$tag" ]]; then
    warn "No release tag to delete"
    exit 0
  fi
  if ! node "$SCRIPT_DIR/ios-release-tag.mjs" valid-tag --tag "$tag"; then
    fail "Refusing to delete unexpected tag: $tag"
  fi
  local delete_output delete_status
  set +e
  delete_output=$(git push origin ":refs/tags/$tag" 2>&1)
  delete_status=$?
  set -e
  printf '%s\n' "$delete_output"
  if [[ "$delete_status" -eq 0 ]]; then
    echo "Deleted unshipped release tag $tag"
    exit 0
  fi
  if scope_denied "$delete_output"; then
    warn "Could not delete unshipped release tag $tag. TestFlight already failed."
    exit 0
  fi
  fail "Failed to delete unshipped release tag $tag"
}

if [[ "${1:-}" == "delete" ]]; then
  delete_tag
fi

RELEASE_TYPE="${RELEASE_TYPE:-testflight}"
GITHUB_SHA="${GITHUB_SHA:?GITHUB_SHA is required}"

if [[ ! -f "$PBXPROJ" ]]; then
  fail "Missing $PBXPROJ"
fi

version=$(node "$SCRIPT_DIR/ios-release-tag.mjs" version "$PBXPROJ")
build_number=$(date -u +%Y%m%d%H%M%S)
tag=$(node "$SCRIPT_DIR/ios-release-tag.mjs" tag \
  --version "$version" \
  --build "$build_number" \
  --deployment "$RELEASE_TYPE")

out "version=$version"
out "build_number=$build_number"
out "tag=$tag"

head_sha=$(git rev-parse HEAD)
if [[ "$head_sha" != "$GITHUB_SHA" ]]; then
  fail "Checkout $head_sha is not the release commit $GITHUB_SHA"
fi

remote=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" || true)
existing=$(printf '%s' "$remote" | node "$SCRIPT_DIR/ios-release-tag.mjs" peeled-commit --tag "$tag" || true)
if [[ -n "$existing" ]]; then
  if [[ "$existing" == "$GITHUB_SHA" ]]; then
    out "pinned=true"
    out "created_tag=false"
    echo "Release tag already points at this commit: $tag"
    exit 0
  fi
  out "pinned=false"
  out "created_tag=false"
  warn "Release tag $tag already points at $existing, not $GITHUB_SHA. Leaving it in place."
  exit 0
fi

git config user.name "GitHub Actions"
git config user.email "actions@github.com"
git tag -a "$tag" -m "iOS Release $tag

Build: $build_number
Deployment: $RELEASE_TYPE
Commit: $GITHUB_SHA"

push_output=""
push_status=0
set +e
push_output=$(git push origin "refs/tags/$tag" 2>&1)
push_status=$?
set -e
printf '%s\n' "$push_output"

if [[ "$push_status" -eq 0 ]]; then
  out "pinned=true"
  out "created_tag=true"
  echo "Pinned release tag $tag at $GITHUB_SHA"
  exit 0
fi

remote_after=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" || true)
existing_after=$(printf '%s' "$remote_after" | node "$SCRIPT_DIR/ios-release-tag.mjs" peeled-commit --tag "$tag" || true)
if [[ "$existing_after" == "$GITHUB_SHA" ]]; then
  out "pinned=true"
  out "created_tag=true"
  echo "Release tag $tag is already pinned at $GITHUB_SHA"
  exit 0
fi

git tag -d "$tag" >/dev/null 2>&1 || true
out "pinned=false"
out "created_tag=false"
if scope_denied "$push_output"; then
  warn "Could not pin $tag at $GITHUB_SHA because main's workflow files already differ. TestFlight will continue. GitHub release evidence may be missing."
  exit 0
fi
fail "Failed to pin release tag $tag"
