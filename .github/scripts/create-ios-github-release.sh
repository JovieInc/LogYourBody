#!/usr/bin/env bash
# Publish the GitHub Release for a tag pinned to the built commit.
#
# --target is sent only when that tag does not exist yet. Passing the built
# SHA after main's workflow files have changed makes the Releases API require
# a workflow scope GITHUB_TOKEN cannot hold (HTTP 403 Resource not accessible
# by integration). When the tag already exists, omit --target so the release
# stays on the built commit. A scope refusal warns and exits 0; TestFlight has
# already succeeded. Other errors still fail the job.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

fail() {
  echo "::error::$1" >&2
  exit 1
}

warn() {
  echo "::warning::$1" >&2
}

RELEASE_TYPE="${RELEASE_TYPE:-testflight}"
RELEASE_VERSION="${RELEASE_VERSION:?RELEASE_VERSION is required}"
RELEASE_BUILD="${RELEASE_BUILD:?RELEASE_BUILD is required}"
GITHUB_SHA="${GITHUB_SHA:?GITHUB_SHA is required}"
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:?GITHUB_SERVER_URL is required}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
RELEASE_ACTOR="${RELEASE_ACTOR:-github-actions[bot]}"

if [[ ! "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  fail "Invalid GITHUB_SHA"
fi

tag=$(node "$SCRIPT_DIR/ios-release-tag.mjs" tag \
  --version "$RELEASE_VERSION" \
  --build "$RELEASE_BUILD" \
  --deployment "$RELEASE_TYPE")

if gh release view "$tag" >/dev/null 2>&1; then
  echo "Release already exists: $tag"
  exit 0
fi

remote=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" || true)
tag_commit=$(printf '%s' "$remote" | node "$SCRIPT_DIR/ios-release-tag.mjs" peeled-commit --tag "$tag" || true)
if [[ -z "$tag_commit" ]]; then
  mode="create"
else
  mode=$(node "$SCRIPT_DIR/ios-release-tag.mjs" target-mode \
    --tag-commit "$tag_commit" \
    --head "$GITHUB_SHA")
fi

if [[ "$mode" == "mismatch" ]]; then
  warn "Release tag $tag points at $tag_commit, not $GITHUB_SHA. Not publishing this build onto that tag."
  exit 0
fi

prerelease=false
installation="- **TestFlight**: Available for all testers"
if [[ "$RELEASE_TYPE" == "app_store" ]]; then
  installation="- **App Store**: Pending review"
else
  prerelease=true
fi

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
## 📱 iOS Release $tag

**Build Number**: $RELEASE_BUILD
**Deployment**: $RELEASE_TYPE
**Version**: ios-v$RELEASE_VERSION

### Changes
This release includes changes that passed the main-branch release workflow.

### Deployment Info
- **Environment**: Production
- **Commit**: $GITHUB_SHA
- **Deployed by**: @$RELEASE_ACTOR
- **Workflow**: [View Run]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID)

### Installation
$installation

---
*Automated release via three-loop CI/CD system*
EOF

args=(release create "$tag" --title "iOS Release $tag" --notes-file "$notes")
if [[ "$prerelease" == "true" ]]; then
  args+=(--prerelease)
fi
if [[ "$mode" == "create" ]]; then
  args+=(--target "$GITHUB_SHA")
fi

create_output=""
create_status=0
set +e
create_output=$(gh "${args[@]}" 2>&1)
create_status=$?
set -e
printf '%s\n' "$create_output"
if [[ "$create_status" -eq 0 ]]; then
  exit 0
fi
if printf '%s' "$create_output" | node "$SCRIPT_DIR/ios-release-tag.mjs" scope-denied; then
  warn "GitHub release was not created for $tag at $GITHUB_SHA because main's workflow files differ and GITHUB_TOKEN cannot take the workflow scope. TestFlight already succeeded."
  exit 0
fi
fail "Failed to create GitHub release $tag"
