#!/usr/bin/env bash

set -euo pipefail

corepack pnpm dlx node@24.12.0 node_modules/eve/bin/eve.js "$@"
