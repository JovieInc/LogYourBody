# Configure iOS Code Signing for TestFlight Deployments

## Overview

To deploy to TestFlight via GitHub Actions, you need:
1. **Apple Developer Certificate** (p12 file)
2. **Provisioning Profile** (App Store distribution)
3. **App Store Connect API Key** (for upload)

## Required Secrets Per Environment

Add these secrets to each environment that deploys to TestFlight:
- `development` - For rapid alpha builds
- `Preview` - For beta builds
- `Production` - For release builds

### Secrets Needed:
1. `IOS_P12_BASE64` - Certificate in base64 format
2. `IOS_P12_PASSWORD` - Certificate password
3. `IOS_PROVISIONING_PROFILE_BASE64` - Provisioning profile in base64
4. `ASC_API_KEY_JSON` - App Store Connect API key (already configured)

## Step 1: Create/Export Certificate

### Option A: Using Xcode (Recommended)
1. Open Xcode → Preferences → Accounts
2. Select your Apple ID
3. Click "Manage Certificates"
4. Click "+" → "Apple Distribution"
5. Right-click the certificate → "Export Certificate"
6. Save as `distribution.p12` with a strong password

### Option B: Using Keychain Access
1. Open Keychain Access
2. Find "Apple Distribution: [Your Name]" certificate
3. Right-click → Export
4. Save as `distribution.p12` with a password

## Step 2: Create Provisioning Profile

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to Certificates, IDs & Profiles
3. Click Profiles → "+"
4. Select "App Store" distribution
5. Select your App ID (com.logyourbody.app)
6. Select your distribution certificate
7. Name it "LogYourBody App Store"
8. Download the `.mobileprovision` file

## Step 3: Convert to Base64

```bash
# Convert certificate to base64
base64 -i distribution.p12 -o certificate.txt

# Convert provisioning profile to base64
base64 -i "LogYourBody_App_Store.mobileprovision" -o profile.txt
```

## Step 4: Add Secrets to GitHub

### Using the Script (Recommended)
```bash
# For each environment
./scripts/add-ios-codesigning-secrets.sh development
./scripts/add-ios-codesigning-secrets.sh Preview
./scripts/add-ios-codesigning-secrets.sh Production
```

### Manual Method
1. Go to https://github.com/JovieInc/LogYourBody/settings/environments
2. Select an environment (e.g., `development`)
3. Add each secret:
   - `IOS_P12_BASE64` - Contents of certificate.txt
   - `IOS_P12_PASSWORD` - Your certificate password
   - `IOS_PROVISIONING_PROFILE_BASE64` - Contents of profile.txt

## Step 5: Verify App Store Connect API Key

The workflows also need App Store Connect API access. Check if it's configured:

```bash
gh secret list | grep ASC_API_KEY_JSON
```

If missing, see "Setting up App Store Connect API Key" below.

## Step 6: Update Fastlane Configuration

Ensure your Fastfile has the correct bundle identifier and team ID:

```ruby
# In apps/ios/fastlane/Fastfile
app_identifier "com.logyourbody.app"
team_id ENV["APPLE_TEAM_ID"]
```

## Setting up App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to Users and Access → Keys
3. Click "+" to create a new key
4. Name: "GitHub Actions CI"
5. Access: "App Manager" role
6. Download the .p8 key file (save it securely!)
7. Note the Key ID and Issuer ID

Create a JSON file:
```json
{
  "key_id": "YOUR_KEY_ID",
  "issuer_id": "YOUR_ISSUER_ID",
  "key": "-----BEGIN PRIVATE KEY-----\nYOUR_KEY_CONTENT\n-----END PRIVATE KEY-----",
  "in_house": false
}
```

Add as repository secret (not environment):
```bash
gh secret set ASC_API_KEY_JSON < api-key.json
```

## Troubleshooting

### Certificate Issues
- Ensure certificate is "Apple Distribution" not "Apple Development"
- Certificate must not be expired
- Password must match exactly

### Provisioning Profile Issues
- Profile must be "App Store" distribution type
- Must include the certificate you're using
- Must match the app's bundle identifier

### Build Failures
- Check Xcode project signing settings
- Ensure "Automatically manage signing" is OFF for Release
- Team ID must match your Apple Developer account

## Security Notes
- Delete local certificate files after uploading to GitHub
- Use strong passwords for p12 files
- Rotate certificates annually
- Never commit certificates to repository