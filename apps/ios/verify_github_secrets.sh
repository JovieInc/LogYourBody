#!/bin/bash

# Script to verify all required GitHub secrets are set
# Run this in GitHub Actions to check your configuration

echo "=== Verifying GitHub Secrets Configuration ==="
echo

# Function to check if a secret is set
check_secret() {
    local secret_name=$1
    local secret_value=$2
    
    if [ -z "$secret_value" ]; then
        echo "❌ $secret_name is NOT set"
        return 1
    else
        # Show partial value for verification (first 4 chars)
        echo "✅ $secret_name is set (starts with: ${secret_value:0:4}...)"
        return 0
    fi
}

# Track if all secrets are set
all_set=true

echo "1. App Store Connect API Authentication:"
check_secret "APP_STORE_CONNECT_API_KEY_ID" "$APP_STORE_CONNECT_API_KEY_ID" || all_set=false
check_secret "APP_STORE_CONNECT_API_KEY_ISSUER_ID" "$APP_STORE_CONNECT_API_KEY_ISSUER_ID" || all_set=false
check_secret "APP_STORE_CONNECT_API_KEY" "$APP_STORE_CONNECT_API_KEY" || all_set=false
echo

echo "2. Match Configuration:"
check_secret "MATCH_PASSWORD" "$MATCH_PASSWORD" || all_set=false
check_secret "MATCH_GIT_URL" "$MATCH_GIT_URL" || all_set=false
check_secret "MATCH_GIT_BASIC_AUTHORIZATION" "$MATCH_GIT_BASIC_AUTHORIZATION" || all_set=false
echo

echo "3. Apple Developer Account:"
check_secret "APPLE_TEAM_ID" "$APPLE_TEAM_ID" || all_set=false
check_secret "APP_STORE_APP_ID" "$APP_STORE_APP_ID" || all_set=false
echo

echo "4. Optional (for fallback):"
check_secret "FASTLANE_USER" "$FASTLANE_USER" || echo "   (This is optional)"
check_secret "FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD" "$FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD" || echo "   (This is optional)"
echo

if [ "$all_set" = true ]; then
    echo "✅ All required secrets are configured!"
else
    echo "❌ Some required secrets are missing. Please add them in GitHub Settings → Secrets"
    exit 1
fi