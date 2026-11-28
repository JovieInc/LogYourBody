#!/usr/bin/env bash
set -euo pipefail

IOS_DIR="${IOS_DIR:-$(pwd)}"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"

cd "$IOS_DIR"

# Discover reusable devices without loading the project or resolving packages.
# Run 40785926339 spent over a minute in -showdestinations, then migrated a new
# device. The later build still verifies the selected destination against the scheme.
SIMULATOR_ID="$(
  xcrun simctl list --json | ruby -rjson -e '
    inventory = JSON.parse(STDIN.read)
    candidates = inventory.fetch("runtimes").flat_map do |runtime|
      next [] unless runtime.fetch("identifier").start_with?("com.apple.CoreSimulator.SimRuntime.iOS-") &&
                     runtime["isAvailable"] == true

      inventory.fetch("devices").fetch(runtime.fetch("identifier"), []).map do |device|
        name = device.fetch("name", "")
        next unless device["isAvailable"] == true && name.start_with?("iPhone") && !device.fetch("udid", "").empty?

        rank = if name == "iPhone 16"
                 0
               elsif name.include?("iPhone 16")
                 1
               elsif name.include?("iPhone 17")
                 2
               elsif name.include?("iPhone 15")
                 3
               else
                 4
               end
        [device, [rank, runtime.fetch("version").scan(/\d+/).map { |part| -part.to_i },
                  device["state"] == "Booted" ? 0 : 1, device.fetch("udid")]]
      end.compact
    end
    preferred = candidates.min_by(&:last)
    puts preferred.first.fetch("udid") if preferred
  '
)"

if [[ -z "$SIMULATOR_ID" ]]; then
  RUNTIME_ID="$(
    xcrun simctl list runtimes --json | ruby -rjson -e '
      runtimes = JSON.parse(STDIN.read).fetch("runtimes", [])
      candidates = runtimes.select do |runtime|
        runtime["platform"] == "iOS" && runtime["isAvailable"] != false
      end

      preferred = candidates.max_by do |runtime|
        runtime.fetch("version", "").scan(/\d+/).map(&:to_i)
      end

      puts preferred["identifier"] if preferred
    '
  )"

  DEVICE_TYPE_ID="$(
    xcrun simctl list devicetypes --json | ruby -rjson -e '
      device_types = JSON.parse(STDIN.read).fetch("devicetypes", [])
      candidates = device_types.select { |device| device.fetch("name", "").include?("iPhone") }

      preferred = candidates.min_by do |device|
        name = device.fetch("name", "")
        rank =
          if name == "iPhone 16"
            0
          elsif name.include?("iPhone 16")
            1
          elsif name.include?("iPhone 17")
            2
          elsif name.include?("iPhone 15")
            3
          else
            4
          end

        [rank, name]
      end

      puts preferred["identifier"] if preferred
    '
  )"

  if [[ -n "$RUNTIME_ID" && -n "$DEVICE_TYPE_ID" ]]; then
    SIMULATOR_ID="$(xcrun simctl create "LYB CI iPhone" "$DEVICE_TYPE_ID" "$RUNTIME_ID")"
  fi
fi

# Boot the chosen simulator and wait for it to finish booting before any test
# invocation. A stock simulator left for xcodebuild to boot made every hosted
# test invocation spend 5-9 min launching the runner (run 38320479871); the
# created-and-booted fallback simulator launched it in 24-60s (#1379 probe).

# Every wait here is bounded: a wedged CoreSimulator previously kept
# `simctl bootstatus` running for the entire workflow step (runs 41400440890
# and 41406257126 burned the full 52-minute launch-quality budget before the
# first test). Only a timeout (124) takes the restart-once repair and then the
# existing exit 70 "simulator unavailable" path. A real simctl status still
# aborts the script with that status, the same as an unbounded `set -e` call.
SIM_BOOT_TIMEOUT_SECONDS="${SIM_BOOT_TIMEOUT_SECONDS:-300}"
SIM_SHUTDOWN_TIMEOUT_SECONDS="${SIM_SHUTDOWN_TIMEOUT_SECONDS:-120}"

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]

process = subprocess.Popen(command, start_new_session=True)
try:
    sys.exit(process.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=30)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)
PY
}

# Return 0 on success and 124 on timeout. Any other status exits the script.
bounded_simctl() {
  local timeout_seconds="$1"
  shift
  local status
  set +e
  run_with_timeout "$timeout_seconds" "$@"
  status=$?
  set -e
  if [[ "$status" -eq 124 ]]; then
    return 124
  fi
  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi
}

exit_if_restart_timed_out() {
  local action="$1"
  echo "::error::Simulator $SIMULATOR_ID ${action} timed out after restart." >&2
  exit 70
}

restart_simulator_once() {
  if ! bounded_simctl "$SIM_SHUTDOWN_TIMEOUT_SECONDS" xcrun simctl shutdown "$SIMULATOR_ID" >&2; then
    exit_if_restart_timed_out "shutdown"
  fi
  if ! bounded_simctl "$SIM_BOOT_TIMEOUT_SECONDS" xcrun simctl boot "$SIMULATOR_ID" >&2; then
    exit_if_restart_timed_out "boot"
  fi
  if ! bounded_simctl "$SIM_BOOT_TIMEOUT_SECONDS" xcrun simctl bootstatus "$SIMULATOR_ID" -b >&2; then
    exit_if_restart_timed_out "bootstatus"
  fi
}

testmanager_socket_ready() {
  local socket_path
  socket_path="$(xcrun simctl getenv "$SIMULATOR_ID" TESTMANAGERD_SIM_SOCK)" || return 1
  [[ -n "$socket_path" && -S "$socket_path" ]]
}

if [[ -n "$SIMULATOR_ID" ]]; then
  boot_started="$(date +%s)"
  # boot can report "already booted"; bootstatus must still succeed.
  # Bound the call so a wedged first boot cannot hang, and ignore its status.
  run_with_timeout "$SIM_BOOT_TIMEOUT_SECONDS" xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  # A device that never finishes booting gets one restart; a still stuck
  # device exits 70. An immediate bootstatus failure keeps its own status.
  if ! bounded_simctl "$SIM_BOOT_TIMEOUT_SECONDS" xcrun simctl bootstatus "$SIMULATOR_ID" -b >&2; then
    echo "::warning::Simulator $SIMULATOR_ID did not finish booting within ${SIM_BOOT_TIMEOUT_SECONDS}s; restarting it once before tests." >&2
    restart_simulator_once
    if ! testmanager_socket_ready; then
      echo "::error::Simulator $SIMULATOR_ID still has no testmanagerd socket after restart." >&2
      exit 70
    fi
  fi
  # A persistent Mac can retain a booted device whose launchd socket vanished
  # (run 40597923369). Repair only this device, once, before admitting tests.
  if ! testmanager_socket_ready; then
    echo "::warning::Simulator $SIMULATOR_ID has no testmanagerd socket; restarting it once before tests." >&2
    restart_simulator_once
    if ! testmanager_socket_ready; then
      echo "::error::Simulator $SIMULATOR_ID still has no testmanagerd socket after restart." >&2
      exit 70
    fi
  fi
  echo "Simulator $SIMULATOR_ID ready in $(( $(date +%s) - boot_started ))s" >&2
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "::error::No available xcodebuild iPhone simulator destination found for the iOS quality gate." >&2
  xcrun simctl list runtimes >&2 || true
  xcrun simctl list devicetypes >&2 || true
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations >&2 || true
  exit 70
fi

printf 'platform=iOS Simulator,id=%s\n' "$SIMULATOR_ID"
