#!/bin/bash

# Script to update branch protection rules using direct API calls
set -e

REPO="JovieInc/LogYourBody"

echo "🔄 Updating branch protection rules for three-loop CI/CD system..."
echo ""

# Get GitHub token from gh auth
TOKEN=$(gh auth token)
if [ -z "$TOKEN" ]; then
    echo "❌ Error: Not authenticated with GitHub CLI"
    echo "Run: gh auth login"
    exit 1
fi

# Function to update branch protection
update_branch_protection() {
    local BRANCH=$1
    local PAYLOAD=$2
    local DESC=$3
    
    echo "📋 Updating $BRANCH branch: $DESC"
    
    # Make API call
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$PAYLOAD" \
        "https://api.github.com/repos/$REPO/branches/$BRANCH/protection")
    
    # Extract status code
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Successfully updated $BRANCH"
    else
        echo "❌ Failed to update $BRANCH (HTTP $HTTP_CODE)"
        echo "Response: $BODY" | jq . 2>/dev/null || echo "$BODY"
        return 1
    fi
}

# Dev branch - no PR reviews
DEV_PAYLOAD='{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci-summary"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}'

# Preview branch - 0 reviews for auto-merge
PREVIEW_PAYLOAD='{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci-summary"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}'

# Main branch - native merge queue + CI Summary is the gate; no human review required
MAIN_PAYLOAD='{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci-summary"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}'

# Update branches
update_branch_protection "dev" "$DEV_PAYLOAD" "Rapid loop, no reviews"
update_branch_protection "preview" "$PREVIEW_PAYLOAD" "Confidence loop, auto-merge friendly"
update_branch_protection "main" "$MAIN_PAYLOAD" "Release loop, queue-gated, no required reviews"

echo ""
echo "🔍 Verifying changes:"
for branch in dev preview main; do
    echo -n "  $branch: "
    gh api "repos/$REPO/branches/$branch/protection/required_status_checks" \
        --jq '.contexts | join(", ")' 2>/dev/null || echo "Error"
done

echo ""
echo "✨ Branch protection updated for three-loop CI/CD!"
echo ""
echo "📊 New configuration:"
echo "  • Dev → ci-summary (rapid loop)"
echo "  • Preview → ci-summary (confidence loop)" 
echo "  • Main → ci-summary (release loop)"