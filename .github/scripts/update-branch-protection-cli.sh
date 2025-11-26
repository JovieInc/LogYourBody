#!/bin/bash

# Script to update branch protection rules for the three-loop CI/CD system
# Uses GitHub CLI (gh) for authentication

set -e

REPO="JovieInc/LogYourBody"

echo "🔄 Updating branch protection rules for three-loop CI/CD system..."
echo "Repository: $REPO"
echo ""

# Function to update branch protection using gh api
update_branch_protection() {
    local BRANCH=$1
    local REVIEWS_REQUIRED=$2
    local REQUIRE_CODE_OWNERS=$3
    local REQUIRE_CONVERSATION_RESOLUTION=$4
    
    echo "📋 Updating protection for branch: $BRANCH"
    
    # Build the review requirements JSON
    local REVIEW_REQUIREMENTS=""
    if [ "$REVIEWS_REQUIRED" -ge 0 ]; then
        REVIEW_REQUIREMENTS=$(cat <<EOF
{
  "required_approving_review_count": $REVIEWS_REQUIRED,
  "dismiss_stale_reviews": true,
  "require_code_owner_reviews": $REQUIRE_CODE_OWNERS
}
EOF
)
    else
        REVIEW_REQUIREMENTS="null"
    fi
    
    # Update branch protection using gh api
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$REPO/branches/$BRANCH/protection" \
        -f "required_status_checks[strict]=true" \
        -f "required_status_checks[contexts][]=ci-summary" \
        -f "enforce_admins=false" \
        --field "required_pull_request_reviews=$REVIEW_REQUIREMENTS" \
        -F "restrictions=null" \
        -f "allow_force_pushes=false" \
        -f "allow_deletions=false" \
        -f "required_conversation_resolution=$REQUIRE_CONVERSATION_RESOLUTION" \
        -f "lock_branch=false" \
        -f "allow_fork_syncing=true" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully updated $BRANCH branch protection"
        echo "   - Required status check: ci-summary"
        if [ "$REVIEWS_REQUIRED" -ge 0 ]; then
            echo "   - Required reviews: $REVIEWS_REQUIRED"
            echo "   - Code owner reviews: $REQUIRE_CODE_OWNERS"
        fi
        echo "   - Conversation resolution: $REQUIRE_CONVERSATION_RESOLUTION"
    else
        echo "❌ Failed to update $BRANCH branch protection"
        return 1
    fi
    echo ""
}

# First, let's check the current status
echo "📊 Current branch protection status:"
for branch in dev preview main; do
    echo -n "  $branch: "
    gh api "repos/$REPO/branches/$branch/protection/required_status_checks" --jq '.contexts[]' 2>/dev/null | tr '\n' ' ' || echo "Not protected"
    echo ""
done
echo ""

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
echo "🔍 Verifying the changes:"
for branch in dev preview main; do
    echo -n "  $branch: "
    gh api "repos/$REPO/branches/$branch/protection/required_status_checks" --jq '.contexts[]' 2>/dev/null | tr '\n' ' '
    echo ""
done