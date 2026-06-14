#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"

cd "$IOS_DIR"

swiftlint lint --strict

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests \
  -only-testing:LogYourBodyTests/BodyScoreShareCardTests \
  test

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard \
  test
