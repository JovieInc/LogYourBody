#!/usr/bin/env bash
# A turn ending does not release a worktree or its dependencies.
set -euo pipefail
if [[ "${1:-}" == "--codex-hook" && $# -eq 1 ]]; then
  echo "Preserved worktree, dependencies, build outputs, and Git metadata." >&2
  printf '%s\n' '{"continue":true}'
elif [[ $# -eq 0 || ( $# -eq 1 && "$1" == "--dry-run" ) ]]; then
  echo "Cleanup report: preserved worktree, dependencies, build outputs, and Git metadata. Use Codex managed worktree archive to save a recoverable snapshot."
else
  echo "Usage: $0 [--codex-hook|--dry-run]" >&2
  exit 2
fi
