#!/bin/bash

echo "This will export your Apple Development certificate."
echo "Note: For TestFlight/App Store, you need an Apple Distribution certificate."
echo ""
echo "Please enter a password for the .p12 file:"
read -s P12_PASSWORD
echo ""

# Export the development certificate
security export -k ~/Library/Keychains/login.keychain -t identities -f pkcs12 -o ~/Downloads/development.p12 -P "$P12_PASSWORD" -T /usr/bin/codesign

if [ -f ~/Downloads/development.p12 ]; then
    echo "✅ Certificate exported to ~/Downloads/development.p12"
    echo ""
    echo "⚠️  This is a DEVELOPMENT certificate."
    echo "For TestFlight, you need an Apple DISTRIBUTION certificate."
else
    echo "❌ Export failed"
fi