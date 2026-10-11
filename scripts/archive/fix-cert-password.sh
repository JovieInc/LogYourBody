#!/bin/bash

echo "🔐 Fixing Certificate Password"
echo "=============================="
echo ""
echo "It seems the certificate password wasn't saved correctly."
echo "Please enter the password you used when exporting the .p12 file:"
read -s CERT_PASSWORD
echo ""

if [ -z "$CERT_PASSWORD" ]; then
    echo "❌ Password cannot be empty!"
    exit 1
fi

# Update password in all environments
for ENV in development Preview Production; do
    echo "Updating password in $ENV..."
    echo -n "$CERT_PASSWORD" | gh secret set IOS_P12_PASSWORD --env "$ENV"
    echo "✅ Updated $ENV"
done

echo ""
echo "✅ Certificate password updated in all environments!"
echo ""
echo "Let's trigger another test..."
rm -f fix-cert-password.sh