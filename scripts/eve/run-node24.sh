#!/usr/bin/env bash

set -euo pipefail

cleanup() {
  node -e "for (const path of ['.output', '.eve/dev-runtime', '.eve/.workflow-data', '.eve/evals', '.eve/compile', '.eve/discovery', '.eve/cache', '.eve/agent-summary.json']) require('node:fs').rmSync(path, { recursive: true, force: true })"
}

trap cleanup EXIT
cleanup

corepack pnpm dlx node@24.12.0 node_modules/eve/bin/eve.js "$@"
