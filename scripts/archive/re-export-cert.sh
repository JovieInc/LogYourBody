#!/bin/bash

echo "🔐 Re-exporting Distribution Certificate"
echo "========================================"
echo ""
echo "Since you don't remember the password, let's export it again."
echo "This time, choose a password you'll remember!"
echo ""
echo "Suggested password tips:"
echo "- Use something simple but secure"
echo "- Write it down somewhere safe"
echo "- You'll need it 3 times (for each environment)"
echo ""
echo "Enter NEW password for the certificate:"
read -s NEW_PASSWORD
echo ""
echo "Confirm password:"
read -s CONFIRM_PASSWORD
echo ""

if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "❌ Passwords don't match!"
    exit 1
fi

if [ -z "$NEW_PASSWORD" ]; then
    echo "❌ Password cannot be empty!"
    exit 1
fi

echo "Exporting certificate with new password..."

# Export with new password
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -o ~/Downloads/distribution_new.p12 -P "$NEW_PASSWORD"

if [ -f ~/Downloads/distribution_new.p12 ]; then
    echo "✅ Certificate exported successfully!"
    echo ""
    echo "Converting to base64..."
    base64 -i ~/Downloads/distribution_new.p12 > ~/Downloads/cert_base64.txt
    
    echo "Updating GitHub secrets..."
    CERT_BASE64=$(cat ~/Downloads/cert_base64.txt)
    
    # Update all environments
    for ENV in development Preview Production; do
        echo ""
        echo "Updating $ENV environment..."
        echo "$CERT_BASE64" | gh secret set IOS_P12_BASE64 --env "$ENV"
        echo "$NEW_PASSWORD" | gh secret set IOS_P12_PASSWORD --env "$ENV"
        echo "✅ Updated $ENV"
    done
    
    # Clean up
    rm -f ~/Downloads/distribution_new.p12
    rm -f ~/Downloads/cert_base64.txt
    rm -f re-export-cert.sh
    
    echo ""
    echo "🎉 All done! Certificate and password updated."
    echo "Your new password has been saved to all environments."
else
    echo "❌ Export failed"
fi