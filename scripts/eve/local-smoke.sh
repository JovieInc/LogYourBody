#!/usr/bin/env bash

set -euo pipefail

cleanup() {
  node -e "for (const path of ['.output', '.eve/dev-runtime', '.eve/.workflow-data', '.eve/evals', '.eve/compile', '.eve/discovery', '.eve/cache', '.eve/agent-summary.json']) require('node:fs').rmSync(path, { recursive: true, force: true })"
}

trap cleanup EXIT
cleanup

export LYB_EVE_LOCAL_SMOKE=1
export LYB_EVE_ALLOW_LOCAL_DEV=1

for connection_state in unconnected connected; do
  export LYB_EVE_CONNECTION_FIXTURE="$connection_state"
  bash scripts/eve/run-node24.sh eval local-smoke \
    --strict \
    --max-concurrency 1 \
    --skip-report
done
