#!/bin/bash

# Script to add iOS code signing secrets to GitHub environment
# Usage: ./scripts/add-ios-codesigning-secrets.sh [environment]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔐 iOS Code Signing Configuration"
echo "================================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed.${NC}"
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Check repository
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ "$REPO" != "JovieInc/LogYourBody" ]; then
    echo -e "${RED}❌ This script should be run from the LogYourBody repository.${NC}"
    exit 1
fi

# Get environment
if [ -n "$1" ]; then
    ENV_NAME="$1"
else
    echo "Available environments: development, Preview, Production"
    echo -n "Enter environment name: "
    read ENV_NAME
fi

echo -e "${BLUE}Configuring environment: $ENV_NAME${NC}"
echo ""

# Function to read file and convert to base64
read_file_base64() {
    local prompt=$1
    local file_type=$2
    
    echo "$prompt"
    echo -n "Enter file path: "
    read file_path
    
    if [ -z "$file_path" ]; then
        echo -e "${YELLOW}⚠️  Skipping (no file provided)${NC}"
        return 1
    fi
    
    # Expand tilde to home directory
    file_path="${file_path/#\~/$HOME}"
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}❌ File not found: $file_path${NC}"
        return 1
    fi
    
    # Convert to base64
    if command -v base64 &> /dev/null; then
        base64 -i "$file_path" 2>/dev/null || base64 "$file_path"
    else
        echo -e "${RED}❌ base64 command not found${NC}"
        return 1
    fi
}

# Add certificate
echo "📝 Certificate (p12 file)"
echo "Export your Apple Distribution certificate from Keychain Access"
if CERT_BASE64=$(read_file_base64 "Path to .p12 certificate file:" "p12"); then
    echo "$CERT_BASE64" | gh secret set IOS_P12_BASE64 --env "$ENV_NAME"
    echo -e "${GREEN}✅ Certificate added${NC}"
else
    echo -e "${YELLOW}⚠️  Certificate not added${NC}"
fi

echo ""

# Add certificate password
echo "📝 Certificate Password"
echo -n "Enter p12 password: "
read -s CERT_PASSWORD
echo ""

if [ -n "$CERT_PASSWORD" ]; then
    echo "$CERT_PASSWORD" | gh secret set IOS_P12_PASSWORD --env "$ENV_NAME"
    echo -e "${GREEN}✅ Certificate password added${NC}"
else
    echo -e "${YELLOW}⚠️  Certificate password not added${NC}"
fi

echo ""

# Add provisioning profile
echo "📝 Provisioning Profile"
echo "Download from Apple Developer Portal (App Store distribution)"
if PROFILE_BASE64=$(read_file_base64 "Path to .mobileprovision file:" "mobileprovision"); then
    echo "$PROFILE_BASE64" | gh secret set IOS_PROVISIONING_PROFILE_BASE64 --env "$ENV_NAME"
    echo -e "${GREEN}✅ Provisioning profile added${NC}"
else
    echo -e "${YELLOW}⚠️  Provisioning profile not added${NC}"
fi

echo ""
echo -e "${GREEN}🎉 iOS code signing configuration complete for $ENV_NAME!${NC}"
echo ""

# Verify secrets
echo "Verifying secrets in $ENV_NAME environment..."
SECRETS=$(gh api repos/$REPO/environments/$ENV_NAME/secrets --jq '.secrets[].name' 2>/dev/null | grep -E "(IOS_P12|IOS_PROVISION)" || echo "None found")
echo "$SECRETS"

echo ""
echo "Next steps:"
echo "1. Configure other environments if needed"
echo "2. Ensure ASC_API_KEY_JSON is set (repository secret)"
echo "3. Push a commit to trigger iOS builds"
echo ""

# Check if ASC_API_KEY_JSON exists
if gh secret list | grep -q "ASC_API_KEY_JSON"; then
    echo -e "${GREEN}✅ ASC_API_KEY_JSON is configured${NC}"
else
    echo -e "${YELLOW}⚠️  ASC_API_KEY_JSON not found - needed for TestFlight upload${NC}"
    echo "   See CONFIGURE_IOS_CODESIGNING.md for setup instructions"
fi