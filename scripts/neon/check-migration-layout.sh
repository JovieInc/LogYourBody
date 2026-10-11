#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

MIGRATIONS_DIR="apps/web/db/migrations"

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "ERROR: Missing canonical Neon migration directory: $MIGRATIONS_DIR" >&2
  exit 1
fi

migration_count="$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d '[:space:]')"
if [[ "$migration_count" -eq 0 ]]; then
  echo "ERROR: Canonical Neon migration directory has no SQL migrations." >&2
  exit 1
fi

echo "Neon migration layout is canonical: $migration_count migrations in $MIGRATIONS_DIR"
