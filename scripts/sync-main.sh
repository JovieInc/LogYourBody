#!/bin/bash

# Post-merge branch sync: fast-forward local main, prune remotes, and delete
# local branches whose upstream is gone (i.e. merged + auto-deleted on GitHub).
# Run this after a PR lands, or any time local branches have piled up.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree is dirty; commit or stash before syncing main" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"

git fetch --prune origin

git checkout main
git pull --ff-only origin main

gone_branches="$(git branch -vv | grep ': gone]' | awk '{print $1}' | grep -v '^main$' || true)"

if [ -n "$gone_branches" ]; then
  echo "Deleting local branches with gone upstreams:"
  echo "$gone_branches"
  echo "$gone_branches" | xargs git branch -d
else
  echo "No stale local branches to delete"
fi

if [ "$current_branch" != "main" ] && git show-ref --verify --quiet "refs/heads/$current_branch"; then
  echo "NOTE: still had local branch '$current_branch' (upstream not gone); left it in place on main"
fi

echo "main is synced and stale branches are pruned"
