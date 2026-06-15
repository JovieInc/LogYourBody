#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$IOS_DIR/test_results/launch-quality-audit/$STAMP}"
RUN_SWIFTLINT="${RUN_SWIFTLINT:-true}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

mkdir -p "$ARTIFACT_DIR"

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

COMMON_XCODEBUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1
)

cd "$IOS_DIR"

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"
fi

xcodebuild \
  "${COMMON_XCODEBUILD_ARGS[@]}" \
  -resultBundlePath "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
  -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests \
  -only-testing:LogYourBodyTests/BodyScoreShareCardTests \
  "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
  test | tee "$ARTIFACT_DIR/launch-quality-unit-tests.log"

xcodebuild \
  "${COMMON_XCODEBUILD_ARGS[@]}" \
  -resultBundlePath "$ARTIFACT_DIR/launch-quality-ui-tests.xcresult" \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchQualityGateCapturesTimelineHomeSurface \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA \
  "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
  test | tee "$ARTIFACT_DIR/launch-quality-ui-tests.log"

cat > "$ARTIFACT_DIR/summary.md" <<SUMMARY
# iOS Launch Quality Audit

- Destination: \`$DESTINATION\`
- Unit coverage: photo timeline HUD policy, Body Score share card layout
- UI coverage: timeline routing, no bottom stats switch card, home/analytics/onboarding screenshot attachments
- Build strategy: unit and UI selectors run separately with simulator parallelism disabled
- Logs and result bundles: \`$ARTIFACT_DIR\`
SUMMARY

echo "Launch quality audit logs written to $ARTIFACT_DIR"
