#!/usr/bin/env bash
set -euo pipefail

# Preflight upload endpoint hosts before release builds or CI smoke.
# Mirrors SupabaseURLBuilder.isValidServiceHost in LogYourBody.

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_invalid_service_host() {
  local host
  host="$(lowercase "$1")"

  if [ -z "$host" ] || [[ "$host" == *"*"* ]] || [[ "$host" != *"."* ]]; then
    return 0
  fi

  return 1
}

fail() {
  echo "::error::$1" >&2
  exit 1
}

require_https_service_url() {
  local name="$1"
  local value="$2"
  local host

  if [ -z "$value" ]; then
    fail "$name must be set."
  fi

  if ! ruby -ruri -e 'uri = URI(ARGV.fetch(0)); exit(uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? ? 0 : 1)' "$value"; then
    fail "$name must be a valid HTTPS URL."
  fi

  host="$(ruby -ruri -e 'uri = URI(ARGV.fetch(0)); print(uri.host || "")' "$value")"
  if is_invalid_service_host "$host"; then
    fail "$name host '$host' is invalid for photo uploads."
  fi
}

SUPABASE_URL="${SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}"
API_BASE_URL="${API_BASE_URL:-https://www.logyourbody.com}"

require_https_service_url "SUPABASE_URL" "$SUPABASE_URL"
require_https_service_url "API_BASE_URL" "$API_BASE_URL"

echo "Upload host preflight passed."