#!/bin/bash

# Script to copy shared legal documents into iOS app bundle

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."
SHARED_LEGAL_DIR="$PROJECT_ROOT/shared/legal"
IOS_RESOURCES_DIR="$SCRIPT_DIR/LogYourBody/Resources/Legal"

# Create Resources/Legal directory if it doesn't exist
mkdir -p "$IOS_RESOURCES_DIR"

# Copy every shared legal document (packages/product-registry/scripts/legal-docs-sync.test.mjs
# fails CI if the iOS copies drift from shared/legal)
echo "Copying legal documents..."

for doc in "$SHARED_LEGAL_DIR"/*.md; do
    name="$(basename "$doc")"
    cp "$doc" "$IOS_RESOURCES_DIR/$name"
    echo "✓ Copied $name"
done

echo "Done!"
