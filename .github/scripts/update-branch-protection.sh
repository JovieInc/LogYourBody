#!/bin/bash

# Script to update branch protection rules for the three-loop CI/CD system
# This script updates the required status checks to use the new orchestrator

set -e

REPO="JovieInc/LogYourBody"
TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"

if [ -z "$TOKEN" ]; then
    echo "❌ Error: Please set GITHUB_TOKEN or GH_TOKEN environment variable"
    echo "You can create a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo (full control of private repositories)"
    exit 1
fi

echo "🔄 Updating branch protection rules for three-loop CI/CD system..."
echo "Repository: $REPO"
echo ""

# Function to update branch protection
update_branch_protection() {
    local BRANCH=$1
    local REVIEWS_REQUIRED=$2
    local REQUIRE_CODE_OWNERS=$3
    local REQUIRE_CONVERSATION_RESOLUTION=$4
    
    echo "📋 Updating protection for branch: $BRANCH"
    
    # Build the JSON payload
    local PAYLOAD=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci-summary"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": $(if [ "$REVIEWS_REQUIRED" -ge 0 ]; then echo "{
    \"required_approving_review_count\": $REVIEWS_REQUIRED,
    \"dismiss_stale_reviews\": true,
    \"require_code_owner_reviews\": $REQUIRE_CODE_OWNERS
  }"; else echo "null"; fi),
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": $REQUIRE_CONVERSATION_RESOLUTION,
  "lock_branch": false,
  "allow_fork_syncing": true
}
EOF
)
    
    # Update branch protection
    RESPONSE=$(curl -s -X PUT \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "https://api.github.com/repos/$REPO/branches/$BRANCH/protection")
    
    # Check if successful
    if echo "$RESPONSE" | grep -q '"url"'; then
        echo "✅ Successfully updated $BRANCH branch protection"
        echo "   - Required status check: ci-summary"
        if [ "$REVIEWS_REQUIRED" -ge 0 ]; then
            echo "   - Required reviews: $REVIEWS_REQUIRED"
            echo "   - Code owner reviews: $REQUIRE_CODE_OWNERS"
        fi
        echo "   - Conversation resolution: $REQUIRE_CONVERSATION_RESOLUTION"
    else
        echo "❌ Failed to update $BRANCH branch protection"
        echo "Response: $RESPONSE"
        return 1
    fi
    echo ""
}

# Update each branch with appropriate settings

# Dev branch - optimized for speed, no reviews required
update_branch_protection "dev" -1 false false

# Preview branch - set up for auto-merge with 0 required reviews
update_branch_protection "preview" 0 false false

# Main branch - production with strict requirements
update_branch_protection "main" 1 true true

echo "🎉 Branch protection rules updated successfully!"
echo ""
echo "📊 Summary of changes:"
echo "- All branches now use 'ci-summary' as the required status check"
echo "- This check aggregates results from the appropriate CI loop:"
echo "  • Dev: Rapid loop (web + iOS fast checks)"
echo "  • Preview: Confidence loop (comprehensive tests)"
echo "  • Main: Release loop (promotion checks)"
echo ""
echo "🔍 To verify the changes:"
echo "gh api repos/$REPO/branches/{branch}/protection | jq '.required_status_checks.contexts'"