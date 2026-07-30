#!/bin/bash

set -euo pipefail

echo "Testing ASC API Key JSON format..."

# This fixture intentionally uses a non-parseable placeholder. Real ASC keys
# must only be supplied through CI/local secret storage.
cat > test_asc.json << 'EOF'
{"key_id":"TEST_KEY_ID","issuer_id":"00000000-0000-0000-0000-000000000000","key":"NOT_A_REAL_PRIVATE_KEY_FIXTURE","in_house":false}
EOF

# Check if JSON is valid
echo "Validating JSON..."
if jq . test_asc.json > /dev/null 2>&1; then
    echo "✅ JSON is valid"
    echo ""
    echo "Parsed values:"
    echo "key_id: $(jq -r .key_id test_asc.json)"
    echo "issuer_id: $(jq -r .issuer_id test_asc.json)"
    echo "in_house: $(jq -r .in_house test_asc.json)"
    echo ""
    echo "Key fixture is intentionally not a PEM/private key."
else
    echo "❌ JSON is invalid"
    exit 1
fi

# Test with ruby (what Fastlane uses)
echo ""
echo "Testing with Ruby (Fastlane's language)..."
ruby -e "
require 'json'
data = JSON.parse(File.read('test_asc.json'))
puts '✅ Ruby can parse the JSON'
puts \"key_id: #{data['key_id']}\"
puts \"issuer_id: #{data['issuer_id']}\"
"

rm -f test_asc.json
