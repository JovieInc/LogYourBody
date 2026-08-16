#!/usr/bin/env bash

set -euo pipefail

cleanup() {
  node -e "for (const path of ['.eve/dev-runtime', '.eve/.workflow-data']) require('node:fs').rmSync(path, { recursive: true, force: true })"
}

trap cleanup EXIT
cleanup

export LYB_EVE_LOCAL_SMOKE=1

corepack pnpm dlx node@24.12.0 \
  node_modules/eve/bin/eve.js eval local-smoke \
  --strict \
  --max-concurrency 1 \
  --skip-report
