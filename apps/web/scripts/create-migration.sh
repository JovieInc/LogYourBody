#!/bin/bash

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
exec "$REPO_ROOT/scripts/web/create-migration.sh" "$@"
