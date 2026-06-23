#!/bin/bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "ERROR: $1" >&2
  status=1
}

if [ ! -d "supabase/migrations" ]; then
  fail "Missing canonical supabase/migrations directory"
fi

app_migration_dirs="$(find apps -path '*/supabase/migrations' -type d -print)"
if [ -n "$app_migration_dirs" ]; then
  fail "App-local Supabase migration directories are not allowed:
$app_migration_dirs"
fi

tracked_app_migrations="$(git ls-files 'apps/*/supabase/migrations/**' | while IFS= read -r file_path; do
  if [ -e "$file_path" ]; then
    printf '%s\n' "$file_path"
  fi
done)"
if [ -n "$tracked_app_migrations" ]; then
  fail "Tracked app-local migration files are not allowed:
$tracked_app_migrations"
fi

if [ ! -f "supabase/config.toml" ]; then
  fail "Missing canonical supabase/config.toml"
fi

if [ "$status" -ne 0 ]; then
  exit "$status"
fi

echo "Supabase migration ownership is canonical"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI not found; skipping live schema drift diff"
  exit 0
fi

diff_output=""
if [ -n "${SUPABASE_SCHEMA_DRIFT_DB_URL:-}" ]; then
  echo "Checking schema drift against SUPABASE_SCHEMA_DRIFT_DB_URL"
  diff_output="$(supabase --workdir supabase db diff --from migrations --to "$SUPABASE_SCHEMA_DRIFT_DB_URL" --schema public,storage 2>&1 || true)"
elif [ "${SUPABASE_SCHEMA_DRIFT_LOCAL:-}" = "1" ]; then
  echo "Checking schema drift against local Supabase"
  diff_output="$(supabase --workdir supabase db diff --local --schema public,storage 2>&1 || true)"
else
  echo "Live schema drift diff skipped. Set SUPABASE_SCHEMA_DRIFT_DB_URL or SUPABASE_SCHEMA_DRIFT_LOCAL=1 to enable it."
  exit 0
fi

if printf '%s\n' "$diff_output" | grep -Fq 'No schema changes found'; then
  echo "No Supabase schema drift detected"
  exit 0
fi

if [ -z "$(printf '%s' "$diff_output" | tr -d '[:space:]')" ]; then
  echo "No Supabase schema drift detected"
  exit 0
fi

echo "$diff_output"
fail "Supabase schema drift detected"
exit "$status"
