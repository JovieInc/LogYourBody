#!/bin/bash

# Script to add Clerk secrets to GitHub environment
# Usage: ./scripts/add-clerk-env-secrets.sh [environment]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔐 GitHub Environment Secrets Configuration for Clerk"
echo "==================================================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed.${NC}"
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Check if we're in the right repository
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ "$REPO" != "JovieInc/LogYourBody" ]; then
    echo -e "${RED}❌ This script should be run from the LogYourBody repository.${NC}"
    echo "Current repo: $REPO"
    exit 1
fi

echo -e "${GREEN}Repository: $REPO ✅${NC}"
echo ""

# Get list of environments
echo "Fetching available environments..."
ENVIRONMENTS=$(gh api repos/$REPO/environments --jq '.environments[].name' 2>/dev/null || echo "")

if [ -z "$ENVIRONMENTS" ]; then
    echo -e "${RED}❌ No environments found. Please create environments first.${NC}"
    exit 1
fi

echo "Available environments:"
echo "$ENVIRONMENTS" | while read -r env; do
    echo "  - $env"
done
echo ""

# Select environment
if [ -n "$1" ]; then
    ENV_NAME="$1"
else
    echo "Which environment do you want to configure?"
    echo -n "Enter environment name: "
    read ENV_NAME
fi

# Validate environment exists
if ! echo "$ENVIRONMENTS" | grep -q "^$ENV_NAME$"; then
    echo -e "${RED}❌ Environment '$ENV_NAME' not found.${NC}"
    exit 1
fi

echo -e "${GREEN}Configuring environment: $ENV_NAME${NC}"
echo ""

# Function to add a secret to an environment
add_env_secret() {
    local env=$1
    local secret_name=$2
    local secret_prompt=$3
    
    echo ""
    echo "📝 $secret_name"
    echo "$secret_prompt"
    
    # Check if it's a production environment
    if [[ "$env" == "production"* ]]; then
        echo -e "${YELLOW}Note: For production, use 'pk_live_' and 'sk_live_' keys${NC}"
    else
        echo -e "${YELLOW}Note: For development/preview, use 'pk_test_' and 'sk_test_' keys${NC}"
    fi
    
    echo -n "Enter value: "
    read -s secret_value
    echo ""
    
    if [ -z "$secret_value" ]; then
        echo -e "${YELLOW}⚠️  Skipping $secret_name (no value provided)${NC}"
        return
    fi
    
    # Validate format
    if [[ "$secret_name" == "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" && ! "$secret_value" =~ ^pk_ ]]; then
        echo -e "${YELLOW}⚠️  Warning: Publishable key should start with 'pk_'${NC}"
    fi
    if [[ "$secret_name" == "CLERK_SECRET_KEY" && ! "$secret_value" =~ ^sk_ ]]; then
        echo -e "${YELLOW}⚠️  Warning: Secret key should start with 'sk_'${NC}"
    fi
    
    # Add secret to environment
    echo "$secret_value" | gh secret set "$secret_name" --env "$env" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $secret_name added to $env environment${NC}"
    else
        echo -e "${RED}❌ Failed to add $secret_name to $env environment${NC}"
        echo "You may need to add it manually through the GitHub UI"
    fi
}

echo "Adding Clerk secrets to $ENV_NAME environment..."
echo "=============================================="

# Add publishable key
add_env_secret "$ENV_NAME" "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "Enter your Clerk publishable key:"

# Add secret key
add_env_secret "$ENV_NAME" "CLERK_SECRET_KEY" "Enter your Clerk secret key:"

echo ""
echo -e "${GREEN}🎉 Configuration complete for $ENV_NAME environment!${NC}"
echo ""

# Show current environment secrets (names only)
echo "Current secrets in $ENV_NAME environment:"
gh api repos/$REPO/environments/$ENV_NAME/secrets --jq '.secrets[].name' 2>/dev/null | grep CLERK || echo "No Clerk secrets found"

echo ""
echo "Next steps:"
echo "1. Configure other environments if needed:"
echo "   ./scripts/add-clerk-env-secrets.sh preview"
echo "   ./scripts/add-clerk-env-secrets.sh production"
echo "2. Push a commit to trigger the CI/CD pipeline"
echo "3. The build should now pass Clerk validation"
echo ""

# Provide re-enable instructions based on environment
if [ "$ENV_NAME" == "dev" ]; then
    echo "To re-enable the Web Rapid Loop deployment:"
    echo "1. Uncomment the deploy-alpha job in .github/workflows/web-rapid-loop.yml"
    echo "2. Commit and push the change"
fi