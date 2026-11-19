#!/bin/bash
set -euo pipefail

readonly xcode_app='/Applications/Xcode_27.1.app'
readonly pinned_developer_dir="$xcode_app/Contents/Developer"

diagnostics() {
  printf 'Available Xcode applications:\n'
  local app
  for app in /Applications/Xcode*.app; do
    [[ -e "$app" ]] && printf '  %s\n' "$app"
  done
  printf 'Current DEVELOPER_DIR=%s\n' "${DEVELOPER_DIR:-<unset>}"
  xcode-select -p 2>&1 || true
  xcodebuild -version 2>&1 || true
}

fail() {
  printf '::error::%s\n' "$1"
  diagnostics
  echo "::error::This workflow's runs-on was left unchanged on purpose. Required image: xcode-27 (not xlarge), or a Tim-authorized Xcode 27.1 install at $xcode_app on jovie-mac. No fallback or installation is performed."
  exit 1
}

[[ -d "$pinned_developer_dir" ]] || fail "Required Xcode 27.1 is missing at $xcode_app."
export DEVELOPER_DIR="$pinned_developer_dir"
printf 'Pinned DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR"
version="$(xcodebuild -version)" || fail 'Cannot read the pinned Xcode version.'
printf '%s\n' "$version"
[[ "${version%%$'\n'*}" == 'Xcode 27.1' ]] || fail 'The pinned application is not Xcode 27.1.'
xcodebuild -showsdks || fail 'Cannot list SDKs from Xcode 27.1.'
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)" || fail 'Cannot resolve the selected iPhone OS SDK version.'
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)" || fail 'Cannot resolve the selected iPhone OS SDK path.'
printf 'Selected iPhone OS SDK: iphoneos%s\nSDK path: %s\n' "$sdk_version" "$sdk_path"
[[ "$sdk_version" =~ ^27\.[0-9]+(\.[0-9]+)?$ ]] || fail "Selected iPhone OS SDK must be 27.x, found $sdk_version."
[[ -n "${GITHUB_ENV:-}" ]] || fail 'GITHUB_ENV is required to persist the Xcode pin.'
printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
