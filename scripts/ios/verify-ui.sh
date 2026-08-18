#!/usr/bin/env bash
# Fast self-verification loop for LogYourBody iOS UI work.
# Greps the XCUI identifier contract, lints UI surfaces, then runs the
# policy tests that UI refactors must keep green.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-auto}"
RUN_UITESTS="${RUN_UITESTS:-false}"

cd "$IOS_DIR"

bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

echo "verify-ui destination: $DESTINATION"

REQUIRED_IDS=(
  continueWithAppleButton
  mvp_weight_text_field
  mvp_keyboard_save_weight_bar_button
  mvp_settings_button
  paywall_title
  paywall_purchase_button
  paywall_restore_purchases_button
  settings_profile_link
  settings_logout_button
  settings_account_subscription_link
  settings_tracking_link
  goal_edit_button
  settings_goal_editor_text_field
  settings_profile_height_row
  settings_integrations_link
  profile_editor_cancel_button
  profile_height_editor
  launch_timeline_surface
  launch_timeline_scrubber
  photo_timeline_root_page_timeline
  photo_timeline_root_page_analytics
  photo_timeline_stats_metric_card_weight
  dashboard_home_timeline_hero
  dashboard_home_quick_answer
  metric_detail_headline
  chat_composer
  chat_send_button
  body_score_onboarding_start_button
  body_score_share_sheet
)

missing=0
for id in "${REQUIRED_IDS[@]}"; do
  if ! rg -q --glob '*.swift' -F "$id" LogYourBody; then
    echo "missing accessibility identifier in app sources: $id" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "UI identifier contract failed. Keep XCUI identifiers stable across visual refactors." >&2
  exit 1
fi

echo "UI identifier contract: ${#REQUIRED_IDS[@]} required ids present"

python3 - <<'PY'
from pathlib import Path
import re, sys
theme = Path("LogYourBody/DesignSystem/Theme.swift").read_text()
block = re.search(r"enum WorldClassScreen:.*?\{(.*?)\n    var id", theme, re.S).group(1)
screens = re.findall(r"case (\w+)", block)
sources = "\n".join(p.read_text(errors="replace") for p in Path("LogYourBody").rglob("*.swift"))
missing = []
for name in screens:
    if re.search(
        rf"worldClassScreen\(\.{name}\)|world_class_screen_{name}|screen:\s*\.{name}\b|:\s*\.{name}\b|^\s+\.{name}\s*$",
        sources,
        re.M,
    ):
        continue
    missing.append(name)
if missing:
    print("missing WorldClassScreen attachments:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
print(f"WorldClassScreen attachments: {len(screens)} screens present in app sources")
PY

if command -v swiftlint >/dev/null 2>&1; then
  # Config `included` still covers the whole iOS target. Keep lint advisory here
  # so pre-existing empty_count findings do not hide the identifier/test loop.
  if ! swiftlint lint --strict \
    LogYourBody/DesignSystem \
    LogYourBody/Views \
    LogYourBody/Components \
    LogYourBody/SettingsComponents.swift \
    LogYourBody/Features/Onboarding; then
    echo "swiftlint reported issues; continuing verify-ui test loop"
  fi
else
  echo "swiftlint not installed; skipping lint"
fi

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:LogYourBodyTests/UIAccessibilityContractTests \
  -only-testing:LogYourBodyTests/LaunchSurfacePolicyTests \
  -only-testing:LogYourBodyTests/ProfileSettingsPolicyTests \
  -only-testing:LogYourBodyTests/AuthSurfacePolicyTests \
  -only-testing:LogYourBodyTests/DashboardTimelineAndPolicyTests \
  -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests \
  -only-testing:LogYourBodyTests/OnboardingStepEntryPolicyTests \
  -only-testing:LogYourBodyTests/PaywallSavingsPolicyTests

if [[ "$RUN_UITESTS" == "true" ]]; then
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSignedOutAppleIsTheOnlyAuthAction \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSubscribedMVPSettingsExposeSubscriptionEscapePaths \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaidMVPFixtureRoutesToDefaultTimelineSurface \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSettingsProfileFieldsOpenDirectEditors
fi

echo "verify-ui: green"
