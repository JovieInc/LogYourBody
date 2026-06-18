#!/usr/bin/env bash
#
# setup-gbrain.sh — point the local gbrain CLI at the shared LogYourBody brain.
#
# gbrain is the personal/org knowledge brain agents query before exploring the
# repo (see "Brain-First Knowledge" in AGENTS.md). The brain lives in Supabase;
# its connection string is a secret, so it is NOT committed. This script resolves
# it from the environment or Doppler and writes it into ~/.gbrain/config.json.
#
# Idempotent and graceful: if gbrain, Doppler, or the secret are unavailable it
# prints why and exits 0, so contributors who don't use gbrain are unaffected and
# this can run in any bootstrap/postinstall flow without breaking it.
#
# Usage:
#   bash scripts/setup-gbrain.sh         # or: pnpm setup:gbrain
#
# Overridable via env:
#   GBRAIN_DATABASE_URL     full postgres URL (wins over Doppler)
#   GBRAIN_DOPPLER_PROJECT  default: jovie-web
#   GBRAIN_DOPPLER_CONFIG   default: dev
#
set -euo pipefail

CONFIG="${GBRAIN_HOME:-$HOME/.gbrain}/config.json"
DOPPLER_PROJECT="${GBRAIN_DOPPLER_PROJECT:-jovie-web}"
DOPPLER_CONFIG="${GBRAIN_DOPPLER_CONFIG:-dev}"

note() { printf '[setup-gbrain] %s\n' "$1"; }

if ! command -v gbrain >/dev/null 2>&1; then
  note "gbrain CLI not installed — skipping. Install it, then re-run to enable brain-first search."
  exit 0
fi

# Resolve the brain database URL: explicit env wins, else Doppler.
URL="${GBRAIN_DATABASE_URL:-}"
SRC="env GBRAIN_DATABASE_URL"
if [ -z "$URL" ] && command -v doppler >/dev/null 2>&1; then
  URL="$(doppler secrets get GBRAIN_DATABASE_URL --plain \
          --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" 2>/dev/null || true)"
  SRC="Doppler $DOPPLER_PROJECT/$DOPPLER_CONFIG"
fi

if [ -z "$URL" ]; then
  note "No GBRAIN_DATABASE_URL found (env or Doppler $DOPPLER_PROJECT/$DOPPLER_CONFIG) — skipping."
  note "Set GBRAIN_DATABASE_URL, or run 'doppler login' with access to $DOPPLER_PROJECT, then re-run."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  note "jq is required to edit the gbrain config safely — install jq, then re-run."
  exit 0
fi

mkdir -p "$(dirname "$CONFIG")"
if [ -f "$CONFIG" ]; then
  # Only rewrite when something actually changes, so this stays a true no-op on re-run.
  current="$(jq -r '.database_url // ""' "$CONFIG")"
  engine="$(jq -r '.engine // ""' "$CONFIG")"
  if [ "$current" = "$URL" ] && [ "$engine" = "supabase" ]; then
    note "gbrain already configured (engine=supabase, url from $SRC) — no change."
  else
    cp "$CONFIG" "$CONFIG.bak"
    tmp="$(mktemp)"
    jq --arg url "$URL" '.database_url = $url | .engine = "supabase"' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    note "Updated gbrain config (engine=supabase, url from $SRC). Backup at $CONFIG.bak."
  fi
else
  cat > "$CONFIG" <<JSON
{
  "engine": "supabase",
  "database_url": "$URL",
  "schema_pack": "gbrain-base-v2"
}
JSON
  note "Wrote new gbrain config (engine=supabase, url from $SRC)."
fi

# Verify connectivity (non-fatal — report but never break the caller).
if gbrain doctor --fast >/dev/null 2>&1; then
  note "gbrain doctor OK — brain-first search is ready (try: gbrain search \"timeline scrubber\")."
else
  note "Config written but 'gbrain doctor' reported issues — run 'gbrain doctor' for detail."
fi

note "For code-aware search (gbrain code-def/code-refs), run '/sync-gbrain --full' in Claude Code to index this repo."
