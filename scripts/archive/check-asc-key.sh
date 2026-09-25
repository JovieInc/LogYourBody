#!/bin/bash

echo "Checking ASC API Key format..."
echo ""
echo "The ASC_API_KEY_JSON should be a single-line JSON string."
echo "Current format check:"
echo ""

# Try to validate it's proper JSON
if gh secret list | grep -q "ASC_API_KEY_JSON"; then
    echo "✅ ASC_API_KEY_JSON secret exists"
    echo ""
    echo "To fix the format issue, you need to ensure the JSON is properly formatted."
    echo "The secret should look like this (all on one line):"
    echo ""
    echo '{"key_id":"YOUR_KEY_ID","issuer_id":"YOUR_ISSUER_ID","key":"-----BEGIN PRIVATE KEY-----\nYOUR_KEY_CONTENT\n-----END PRIVATE KEY-----","in_house":false}'
    echo ""
    echo "Make sure:"
    echo "1. It's valid JSON (use jsonlint.com to check)"
    echo "2. The private key newlines are escaped as \\n"
    echo "3. It's all on one line"
else
    echo "❌ ASC_API_KEY_JSON not found"
fi

rm -f check-asc-key.sh