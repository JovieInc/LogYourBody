# iOS Code Signing Quick Start

## What You Need

1. **Apple Developer Account** with:
   - Valid Apple Distribution certificate
   - App ID created (com.logyourbody.app)
   - App Store provisioning profile

2. **App Store Connect** with:
   - App created
   - API key for automation

## Quick Setup Commands

```bash
# Step 1: Add repository-level secrets (one time)
./scripts/add-ios-repo-secrets.sh
# You'll need:
# - Team ID (find at developer.apple.com → Membership)
# - App Store App ID (find at App Store Connect → App Information)
# - Provisioning Profile name

# Step 2: Export certificate from Keychain
# - Open Keychain Access
# - Find "Apple Distribution: [Your Name]"
# - Right-click → Export → Save as distribution.p12

# Step 3: Download provisioning profile
# - Go to developer.apple.com → Profiles
# - Download your App Store profile

# Step 4: Add to each environment
./scripts/add-ios-codesigning-secrets.sh development
./scripts/add-ios-codesigning-secrets.sh Preview
./scripts/add-ios-codesigning-secrets.sh Production

# Step 5: Verify everything is set up
./scripts/check-ios-secrets.sh
```

## Finding Your IDs

### Team ID

1. Go to https://developer.apple.com
2. Click Account → Membership
3. Look for "Team ID" (10 characters like A1B2C3D4E5)

### App Store App ID

1. Go to https://appstoreconnect.apple.com
2. Select your app
3. Go to App Information
4. Look for "Apple ID" (10 digits like 1234567890)

### Bundle ID

Should be: `com.logyourbody.app`

## Common Issues

- **"No identity found"**: Certificate not in keychain
- **"No profiles found"**: Wrong provisioning profile type
- **"Code signing failed"**: Certificate/profile mismatch

## Test Your Setup

After configuration, the iOS Rapid Loop should:

1. Build successfully
2. Upload to TestFlight
3. Show in TestFlight within 5-10 minutes
