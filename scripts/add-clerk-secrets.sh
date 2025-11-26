#!/bin/bash

# Script to add Clerk secrets to GitHub repository
# Usage: ./scripts/add-clerk-secrets.sh

set -e

echo "🔐 GitHub Secrets Configuration for Clerk"
echo "========================================"
echo ""
echo "This script will help you add Clerk secrets to your GitHub repository."
echo "You'll need your Clerk API keys from https://dashboard.clerk.com"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed."
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Check if we're in the right repository
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ "$REPO" != "JovieInc/LogYourBody" ]; then
    echo "❌ This script should be run from the LogYourBody repository."
    echo "Current repo: $REPO"
    exit 1
fi

echo "Repository: $REPO ✅"
echo ""

# Function to add a secret
add_secret() {
    local secret_name=$1
    local secret_prompt=$2
    
    echo ""
    echo "📝 $secret_name"
    echo "$secret_prompt"
    echo -n "Enter value: "
    read -s secret_value
    echo ""
    
    if [ -z "$secret_value" ]; then
        echo "⚠️  Skipping $secret_name (no value provided)"
        return
    fi
    
    echo "$secret_value" | gh secret set "$secret_name"
    echo "✅ $secret_name added successfully"
}

echo "Adding required Clerk secrets..."
echo "================================"

# Add publishable key
add_secret "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "Enter your Clerk publishable key (starts with pk_test_ or pk_live_):"

# Add secret key
add_secret "CLERK_SECRET_KEY" "Enter your Clerk secret key (starts with sk_test_ or sk_live_):"

echo ""
echo "🎉 Clerk secrets configuration complete!"
echo ""
echo "Current secrets:"
gh secret list | grep CLERK || echo "No Clerk secrets found"

echo ""
echo "Next steps:"
echo "1. Push a commit to trigger the CI/CD pipeline"
echo "2. Check the Web Rapid Loop workflow"
echo "3. The build should now pass Clerk validation"
echo ""
echo "To test locally, add these to your .env.local file."