#!/bin/bash

# Script to check iOS deployment secrets configuration
# Usage: ./scripts/check-ios-secrets.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Checking iOS Deployment Secrets"
echo "=================================="
echo ""

# Check repository
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
echo -e "${BLUE}Repository: $REPO${NC}"
echo ""

# Required secrets for iOS deployment
IOS_ENV_SECRETS=(
    "IOS_P12_BASE64"
    "IOS_P12_PASSWORD"
    "IOS_PROVISIONING_PROFILE_BASE64"
)

IOS_REPO_SECRETS=(
    "ASC_API_KEY_JSON"
    "APPLE_TEAM_ID"
    "APP_STORE_APP_ID"
    "IOS_PROVISIONING_PROFILE_NAME"
)

# Check environment secrets
echo -e "${BLUE}Environment Secrets:${NC}"
echo "==================="
for env in development Preview Production; do
    echo -e "\n${BLUE}📁 $env environment:${NC}"
    
    # Get secrets for this environment
    SECRETS=$(gh api repos/$REPO/environments/$env/secrets --jq '.secrets[].name' 2>/dev/null || echo "")
    
    all_present=true
    for secret in "${IOS_ENV_SECRETS[@]}"; do
        if echo "$SECRETS" | grep -q "^$secret$"; then
            echo -e "  ${GREEN}✅ $secret${NC}"
        else
            echo -e "  ${RED}❌ $secret (missing)${NC}"
            all_present=false
        fi
    done
    
    if [ "$all_present" = true ]; then
        echo -e "  ${GREEN}✨ All iOS secrets present!${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Missing iOS secrets${NC}"
        echo -e "  Run: ${BLUE}./scripts/add-ios-codesigning-secrets.sh $env${NC}"
    fi
done

# Check repository-level secrets
echo -e "\n${BLUE}Repository Secrets:${NC}"
echo "=================="
REPO_SECRETS=$(gh secret list --json name -q '.[].name' || echo "")

for secret in "${IOS_REPO_SECRETS[@]}"; do
    if echo "$REPO_SECRETS" | grep -q "^$secret$"; then
        echo -e "${GREEN}✅ $secret${NC}"
    else
        echo -e "${RED}❌ $secret (missing)${NC}"
    fi
done

# Provide guidance
echo -e "\n${BLUE}Setup Guide:${NC}"
echo "============"
echo "1. Certificate & Profile (per environment):"
echo "   - Export Apple Distribution certificate as .p12"
echo "   - Download App Store provisioning profile"
echo "   - Run: ./scripts/add-ios-codesigning-secrets.sh [environment]"
echo ""
echo "2. App Store Connect API Key (repository-level):"
echo "   - Create key at App Store Connect → Users → Keys"
echo "   - Save as JSON and add with: gh secret set ASC_API_KEY_JSON < key.json"
echo ""
echo "3. Team & App Info (repository-level):"
echo "   - APPLE_TEAM_ID: Your 10-character team ID"
echo "   - APP_STORE_APP_ID: Your app's ID in App Store Connect"
echo "   - IOS_PROVISIONING_PROFILE_NAME: Name of your profile"
echo ""
echo "See docs/archive/CONFIGURE_IOS_CODESIGNING.md for detailed instructions."