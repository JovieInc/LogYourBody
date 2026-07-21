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

# Strip the leading '*'/'+ '/' column git branch -vv adds for current/worktree
# branches, then keep only branches whose upstream is gone.
gone_branches="$(git branch -vv | sed -e 's/^[*+] //' | awk '/: gone]/ {print $1}' | grep -v '^main$' || true)"

skipped=""
if [ -n "$gone_branches" ]; then
  echo "Pruning local branches with gone upstreams:"
  while IFS= read -r branch; do
    # PRs squash-merge, so merged branches are not ancestors of main and
    # `git branch -d` always refuses. `git cherry` compares patches instead:
    # no '+' lines means every change is already in main and -D is safe.
    if [ -z "$(git cherry main "$branch" 2>/dev/null | grep '^+' || true)" ]; then
      echo "  deleting $branch (all changes are in main)"
      git branch -D "$branch"
    else
      echo "  keeping $branch (has commits not in main)"
      skipped="$skipped $branch"
    fi
  done <<< "$gone_branches"
else
  echo "No stale local branches to delete"
fi

if [ -n "$skipped" ]; then
  echo "WARNING: branches with work not in main were left in place:$skipped" >&2
fi

if [ "$current_branch" != "main" ] && git show-ref --verify --quiet "refs/heads/$current_branch"; then
  echo "NOTE: still had local branch '$current_branch' (upstream not gone); left it in place on main"
fi

echo "main is synced and stale branches are pruned"
