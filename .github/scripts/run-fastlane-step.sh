#!/usr/bin/env bash
# Run a fastlane command and keep its exit status through tee.
#
# Fastlane prints an upgrade changelog after the command. That changelog is not
# a result: it has contained the word "signing" and failed the App Store
# precheck step. The command status is the failure signal.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "::error::usage: run-fastlane-step.sh <log-file> <command> [args...]" >&2
  exit 2
fi

log_file=$1
shift

"$@" 2>&1 | tee "$log_file"
