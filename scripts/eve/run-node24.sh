#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "eval" ]]; then
  corepack pnpm dlx node@24.12.0 --import ./scripts/eve/eval-recorder-preload.mjs node_modules/eve/bin/eve.js "$@"
else
  corepack pnpm dlx node@24.12.0 node_modules/eve/bin/eve.js "$@"
fi
