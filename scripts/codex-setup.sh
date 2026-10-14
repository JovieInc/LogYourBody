#!/usr/bin/env bash
# The same frozen dependency bootstrap is used locally and in cloud containers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_PIN="$(tr -d '[:space:]' < "$ROOT/.nvmrc")"
NVM_NODE_BIN="${NVM_DIR:-$HOME/.nvm}/versions/node/v${NODE_PIN}/bin"
if [[ -x "$NVM_NODE_BIN/node" ]]; then
  export PATH="$NVM_NODE_BIN:$PATH"
fi
cd "$ROOT"
if [[ "${1:-}" == "--run" ]]; then
  shift
  if [[ $# -eq 0 ]]; then echo "--run requires a pnpm command" >&2; exit 2; fi
  exec pnpm "$@"
fi
if [[ "${1:-}" == "--codex-hook" ]]; then
  if [[ $# -ne 1 ]]; then echo "Usage: $0 [--codex-hook|--run <pnpm command>]" >&2; exit 2; fi
  node "$ROOT/scripts/codex-setup.mjs" >&2
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Log Your Body secret-free dependencies prepared. Native iOS, signing, and authenticated runtime checks require their own environment."}}'
else
  if [[ $# -gt 0 ]]; then echo "Usage: $0 [--codex-hook|--run <pnpm command>]" >&2; exit 2; fi
  exec node "$ROOT/scripts/codex-setup.mjs"
fi
