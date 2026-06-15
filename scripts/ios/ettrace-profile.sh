#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
SIMULATOR_NAME="${SIMULATOR_NAME:-}"
BUNDLE_ID="${BUNDLE_ID:-com.logyourbody.app}"
RUN_DIR="${RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/lyb-ettrace.XXXXXX")}"
ETTRACE_TAG="${ETTRACE_TAG:-v1.1.0}"
ETTRACE_SRC="${ETTRACE_SRC:-$RUN_DIR/ETTrace-src}"
ETTRACE_XCFRAMEWORK="${ETTRACE_XCFRAMEWORK:-$RUN_DIR/ETTrace.xcframework}"
ETTRACE_CAPTURE="${ETTRACE_CAPTURE:-manual}"
CAPTURE_SECONDS="${CAPTURE_SECONDS:-45}"
APP_LAUNCH_ARGS="${APP_LAUNCH_ARGS:--lybUITestPhotoTimelineHUDFixture -lybUITestTimelinePerformanceTraceFixture -lybUITestPhaseInsightFixture -lybUITestGlp1WeeklyCheckInFixture}"

usage() {
  cat <<'USAGE'
Usage: pnpm ios:ettrace-profile

Builds a simulator-only LogYourBody app with ETTrace linked through temporary
xcodebuild flags, embeds ETTrace.framework into the built .app, installs it on
the booted simulator, and writes capture instructions under RUN_DIR.

Environment:
  RUN_DIR                 Output folder. Defaults to a temp directory.
  DESTINATION             xcodebuild simulator destination.
  SIMULATOR_NAME          simctl boot target. Defaults to name= from DESTINATION.
  ETTRACE_XCFRAMEWORK     Existing ETTrace.xcframework to reuse.
  ETTRACE_TAG             ETTrace git tag when building a framework. Default v1.1.0.
  ETTRACE_CAPTURE         manual or launch. Default manual.
  CAPTURE_SECONDS         Seconds to record in launch mode. Default 45.
  APP_LAUNCH_ARGS         Args passed to the app in launch mode.

Examples:
  pnpm ios:ettrace-profile

  ETTRACE_CAPTURE=launch CAPTURE_SECONDS=45 pnpm ios:ettrace-profile
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

if [[ -z "$SIMULATOR_NAME" ]]; then
  SIMULATOR_NAME="$(python3 - "$DESTINATION" <<'PY'
import sys

destination = sys.argv[1]
for part in destination.split(","):
    key, _, value = part.partition("=")
    if key.strip() == "name":
        print(value.strip())
        break
PY
)"
fi

if [[ -z "$SIMULATOR_NAME" ]]; then
  echo "error: SIMULATOR_NAME is required when DESTINATION has no name= segment" >&2
  exit 2
fi

if ! command -v ettrace >/dev/null 2>&1; then
  echo "error: ettrace CLI is not installed. Run: brew install emergetools/homebrew-tap/ettrace" >&2
  exit 1
fi

build_ettrace_xcframework() {
  if [[ -d "$ETTRACE_XCFRAMEWORK" ]]; then
    return 0
  fi

  if [[ ! -d "$ETTRACE_SRC" ]]; then
    git clone --depth 1 --branch "$ETTRACE_TAG" https://github.com/EmergeTools/ETTrace "$ETTRACE_SRC"
  fi

  rm -rf "$RUN_DIR/ETTrace-iphonesimulator.xcarchive" "$ETTRACE_XCFRAMEWORK"
  (
    cd "$ETTRACE_SRC"
    xcodebuild archive \
      -scheme ETTrace \
      -archivePath "$RUN_DIR/ETTrace-iphonesimulator.xcarchive" \
      -sdk iphonesimulator \
      -destination "generic/platform=iOS Simulator" \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      INSTALL_PATH="Library/Frameworks" \
      SKIP_INSTALL=NO \
      CLANG_CXX_LANGUAGE_STANDARD=c++17

    xcodebuild -create-xcframework \
      -framework "$RUN_DIR/ETTrace-iphonesimulator.xcarchive/Products/Library/Frameworks/ETTrace.framework" \
      -output "$ETTRACE_XCFRAMEWORK"
  )
}

find_ettrace_framework() {
  find "$ETTRACE_XCFRAMEWORK" -type d -name ETTrace.framework -path "*simulator*" -print -quit
}

copy_dsyms() {
  local derived_data="$1"
  local dsyms="$2"
  mkdir -p "$dsyms"

  find "$derived_data/Build/Products" -maxdepth 4 -type d -name "*.dSYM" -print0 2>/dev/null |
    while IFS= read -r -d "" dsym; do
      rm -rf "$dsyms/$(basename "$dsym")"
      cp -R "$dsym" "$dsyms/"
    done

  find "$RUN_DIR" -type d -name "ETTrace.framework.dSYM" -print0 2>/dev/null |
    while IFS= read -r -d "" dsym; do
      rm -rf "$dsyms/$(basename "$dsym")"
      cp -R "$dsym" "$dsyms/"
    done
}

write_instructions() {
  local app="$1"
  local dsyms="$2"
  local instructions="$RUN_DIR/run-instructions.md"

  cat > "$instructions" <<EOF
# LogYourBody ETTrace Profile

Run directory: \`$RUN_DIR\`
App: \`$app\`
dSYMs: \`$dsyms\`
Destination: \`$DESTINATION\`
Simulator: \`$SIMULATOR_NAME\`

## Manual Runtime Capture

1. Start ETTrace from this run directory:

\`\`\`bash
cd "$RUN_DIR"
: > .ettrace-capture-start
find "$RUN_DIR" -maxdepth 1 -name 'output_*.json' -delete
ettrace --simulator --verbose --dsyms "$dsyms"
\`\`\`

2. In another terminal or with XcodeBuildMCP, launch and drive the installed app:

\`\`\`bash
xcrun simctl terminate booted "$BUNDLE_ID" || true
xcrun simctl launch booted "$BUNDLE_ID" $APP_LAUNCH_ARGS
\`\`\`

3. Perform one focused flow, for example Avatar -> Photo -> Stats -> Timeline.
4. Stop ETTrace with Ctrl-C.
5. Preserve processed flamegraph output:

\`\`\`bash
PRESERVED_DIR="\$(mktemp -d "$RUN_DIR/run-\$(date +%Y%m%d-%H%M%S).XXXXXX")"
find "$RUN_DIR" -maxdepth 1 -name 'output_*.json' -newer "$RUN_DIR/.ettrace-capture-start" -exec cp {} "\$PRESERVED_DIR/" \\;
ls -la "\$PRESERVED_DIR"
\`\`\`

## Automated Launch Smoke

This script can run a launch-only ETTrace smoke capture:

\`\`\`bash
ETTRACE_CAPTURE=launch CAPTURE_SECONDS=45 RUN_DIR="$RUN_DIR" pnpm ios:ettrace-profile
\`\`\`

Use manual mode for the timeline interaction trace; launch mode is only a
connectivity proof for the ETTrace-instrumented simulator app.
EOF

  echo "Instructions written to $instructions"
}

preserve_outputs() {
  local marker="$1"
  local preserved_dir="$RUN_DIR/run-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$preserved_dir"

  find "$RUN_DIR" -maxdepth 1 -name "output_*.json" -newer "$marker" -print0 |
    while IFS= read -r -d "" json; do
      cp "$json" "$preserved_dir/"
    done

  if find "$preserved_dir" -maxdepth 1 -name "output_*.json" -print -quit | grep -q .; then
    echo "Processed ETTrace output preserved in $preserved_dir"
  else
    echo "warning: no fresh output_*.json files found in $RUN_DIR" >&2
  fi
}

build_ettrace_xcframework

ETTRACE_FRAMEWORK="$(find_ettrace_framework)"
if [[ -z "$ETTRACE_FRAMEWORK" ]]; then
  echo "error: simulator ETTrace.framework not found under $ETTRACE_XCFRAMEWORK" >&2
  exit 1
fi

DERIVED_DATA="$RUN_DIR/DerivedData"
FRAMEWORK_PARENT="$(dirname "$ETTRACE_FRAMEWORK")"
BUILD_LOG="$RUN_DIR/build-ettrace-app.log"

(
  cd "$IOS_DIR"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -sdk iphonesimulator \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    "FRAMEWORK_SEARCH_PATHS=$FRAMEWORK_PARENT" \
    'OTHER_LDFLAGS=$(inherited) -framework ETTrace' \
    build | tee "$BUILD_LOG"
)

APP="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator" -maxdepth 1 -name "$SCHEME.app" -print -quit)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: built app not found in $DERIVED_DATA" >&2
  exit 1
fi

mkdir -p "$APP/Frameworks"
rm -rf "$APP/Frameworks/ETTrace.framework"
ditto "$ETTRACE_FRAMEWORK" "$APP/Frameworks/ETTrace.framework"

DSYMS="$RUN_DIR/dsyms"
copy_dsyms "$DERIVED_DATA" "$DSYMS"

xcrun simctl boot "$SIMULATOR_NAME" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_NAME" -b >/dev/null
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl install booted "$APP"

write_instructions "$APP" "$DSYMS"

if [[ "$ETTRACE_CAPTURE" == "manual" ]]; then
  echo "Prepared ETTrace-instrumented app for manual capture."
  echo "Run directory: $RUN_DIR"
  exit 0
fi

if [[ "$ETTRACE_CAPTURE" != "launch" ]]; then
  echo "error: ETTRACE_CAPTURE must be manual or launch" >&2
  exit 2
fi

if [[ ! -t 1 ]]; then
  echo "warning: ETTrace works best from a TTY; non-TTY launch capture may not produce output." >&2
fi

CAPTURE_MARKER="$RUN_DIR/.ettrace-capture-start"
: > "$CAPTURE_MARKER"
find "$RUN_DIR" -maxdepth 1 -name "output_*.json" -delete

(
  cd "$RUN_DIR"
  ettrace --simulator --verbose --dsyms "$DSYMS"
) | tee "$RUN_DIR/ettrace.log" &
ETTRACE_PID="$!"

sleep 3
xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
read -r -a LAUNCH_ARGS_ARRAY <<< "$APP_LAUNCH_ARGS"
xcrun simctl launch booted "$BUNDLE_ID" "${LAUNCH_ARGS_ARRAY[@]}"
sleep "$CAPTURE_SECONDS"
kill -INT "$ETTRACE_PID" >/dev/null 2>&1 || true
wait "$ETTRACE_PID" || true

preserve_outputs "$CAPTURE_MARKER"
