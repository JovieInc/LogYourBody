#!/usr/bin/env bash
set -euo pipefail

API_KEY="${REVENUE_CAT_PUBLIC_KEY:-${REVENUE_CAT_API_KEY:-${IOS_REVENUE_CAT_API_KEY:-}}}"
APP_USER_ID="${REVENUECAT_PREFLIGHT_APP_USER_ID:-release-preflight}"
REQUIRED_PACKAGES="${REVENUECAT_REQUIRED_PACKAGES:-\$rc_annual:com.logyourbody.app.pro.annual.3daytrial,\$rc_monthly:com.logyourbody.app.pro.monthly.3daytrial}"
OFFERINGS_URL="${REVENUECAT_OFFERINGS_URL:-https://api.revenuecat.com/v1/subscribers/$APP_USER_ID/offerings}"
JSON_FILE="${REVENUECAT_OFFERINGS_JSON_FILE:-}"

fail() {
  echo "::error::$1" >&2
  exit 1
}

is_placeholder() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    ""|*"\$("*|*your-*|*placeholder*|*replace*|*todo*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_value() {
  local name="$1"
  local value="$2"

  if is_placeholder "$value"; then
    fail "$name must be set to a real RevenueCat public API key."
  fi
}

TMP_JSON="$(mktemp)"
cleanup() {
  rm -f "$TMP_JSON"
}
trap cleanup EXIT

require_value "REVENUE_CAT_PUBLIC_KEY" "$API_KEY"

if [ -n "$JSON_FILE" ]; then
  cp "$JSON_FILE" "$TMP_JSON"
else
  HTTP_STATUS="$(
    curl --silent --show-error --location \
      --output "$TMP_JSON" \
      --write-out '%{http_code}' \
      --header "Authorization: Bearer $API_KEY" \
      --header 'X-Platform: ios' \
      "$OFFERINGS_URL"
  )"

  if [ "$HTTP_STATUS" != "200" ]; then
    BODY="$(tr '\n' ' ' < "$TMP_JSON" | cut -c 1-500)"
    fail "RevenueCat offerings preflight failed with HTTP $HTTP_STATUS. Response: $BODY"
  fi
fi

ruby -rjson -e '
  path = ARGV.fetch(0)
  required = ARGV.fetch(1).split(",").map do |pair|
    package_id, product_id = pair.split(":", 2)
    next if package_id.nil? || package_id.empty? || product_id.nil? || product_id.empty?
    [package_id, product_id]
  end.compact

  abort "::error::REVENUECAT_REQUIRED_PACKAGES must include at least one package:product pair." if required.empty?

  data = JSON.parse(File.read(path))
  current_id = data["current_offering_id"].to_s
  offerings = Array(data["offerings"])
  abort "::error::RevenueCat response did not include current_offering_id." if current_id.empty?

  current = offerings.find { |offering| offering["identifier"].to_s == current_id }
  abort "::error::RevenueCat current offering #{current_id.inspect} was not present in offerings response." unless current

  packages = Array(current["packages"])
  missing = []

  required.each do |package_id, product_id|
    match = packages.find do |package|
      package["identifier"].to_s == package_id &&
        package["platform_product_identifier"].to_s == product_id
    end
    missing << "#{package_id}:#{product_id}" unless match
  end

  unless missing.empty?
    available = packages.map do |package|
      "#{package["identifier"]}:#{package["platform_product_identifier"]}"
    end

    warn "::error::RevenueCat current offering #{current_id.inspect} is missing required packages: #{missing.join(", ")}"
    warn "Available packages: #{available.join(", ")}"
    exit 1
  end

  puts "Verified RevenueCat current offering #{current_id} includes #{required.map { |pair| pair.join(":") }.join(", ")}."
' "$TMP_JSON" "$REQUIRED_PACKAGES"
