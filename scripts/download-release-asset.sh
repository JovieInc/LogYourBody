#!/usr/bin/env bash
# Download a pinned release asset, recovering through the official asset API.
set -euo pipefail

release_url="${1:?release URL required}"
asset_url="${2:?asset API URL required}"
sha256="${3:?SHA-256 required}"
output="${4:?output path required}"

if ! curl --fail --silent --show-error --location \
  --retry 3 --retry-all-errors --retry-delay 2 \
  --connect-timeout 30 --max-time 120 \
  "$release_url" -o "$output" ||
  ! printf '%s  %s\n' "$sha256" "$output" | shasum -a 256 --check --strict; then
  # HTTP 200 is insufficient: recover invalid bytes through the same pinned digest.
  # Authenticate only the API request, avoiding the shared anonymous rate limit.
  headers=(--header 'Accept: application/octet-stream')
  if [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(--header "Authorization: Bearer ${GH_TOKEN}")
  fi
  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors --retry-delay 2 \
    --connect-timeout 30 --max-time 120 \
    "${headers[@]}" "$asset_url" -o "$output"
fi

# Neither HTTP error content nor substituted archives may reach extraction.
printf '%s  %s\n' "$sha256" "$output" | shasum -a 256 --check --strict
