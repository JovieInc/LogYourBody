#!/usr/bin/env bash

set -euo pipefail

export LYB_EVE_LOCAL_SMOKE=1

for connection_state in unconnected connected; do
  export LYB_EVE_CONNECTION_FIXTURE="$connection_state"
  bash scripts/eve/run-node24.sh eval local-smoke \
    --strict \
    --max-concurrency 1 \
    --skip-report
done
