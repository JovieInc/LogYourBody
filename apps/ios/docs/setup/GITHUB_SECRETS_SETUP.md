# GitHub Actions Secrets for iOS CI/CD

## Required Secrets for Fastlane Match and App Store Connect

### 1. App Store Connect API Authentication
These are required for API key authentication (recommended over username/password):

- **`APP_STORE_CONNECT_API_KEY_ID`**: `V9NW6ZGUK3`
  - Your API key ID from App Store Connect
  
- **`APP_STORE_CONNECT_API_KEY_ISSUER_ID`**: `c195f569-ff16-40fa-aaff-4fe94e8139ad`
  - The issuer ID for your API key
  
- **`APP_STORE_CONNECT_API_KEY`**: 
  - The actual private key content (PEM format)
  - Should include the full key with:
    ```
    -----BEGIN PRIVATE KEY-----
    [your key content]
    -----END PRIVATE KEY-----
    ```

### 2. Match Configuration
For certificate and provisioning profile management:

- **`MATCH_PASSWORD`**: `Xuwa8gLaHbj3UCC3eC7M`
  - Password to decrypt certificates stored in Match repository
  
- **`MATCH_GIT_URL`**: `https://github.com/itstimwhite/certificates.git`
  - Your private git repository for storing certificates
  
- **`MATCH_GIT_BASIC_AUTHORIZATION`**: 
  - Format: `base64(username:personal_access_token)`
  - Example: If your GitHub username is `itstimwhite` and PAT is `ghp_xxxxx`, run:
    ```bash
    echo -n "itstimwhite:ghp_xxxxx" | base64
    ```
  - This allows Match to access your private certificates repository

### 3. Apple Developer Account
- **`APPLE_TEAM_ID`**: `G24T327LXT`
  - Your Apple Developer Team ID
  
- **`APP_STORE_APP_ID`**: `6740237149`
  - The numeric App Store ID (not bundle ID)
  - Find this in App Store Connect under your app

### 4. Optional (Not currently used but good to have)
- **`FASTLANE_USER`**: `t@timwhite.co`
  - Apple ID email (backup for when API key fails)
  
- **`FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`**: `gmro-cwoj-lvhj-zxub`
  - App-specific password for Apple ID (backup authentication)

## How to Add These Secrets

1. Go to your GitHub repository
2. Navigate to Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Add each secret with the exact name and value listed above

## Verify Your Setup

After adding all secrets, you can verify they're working by checking the CI logs for:
- "✅ App Store Connect API key configured from file"
- "Match successfully synced certificates"
- No errors about missing authentication

## Security Notes

- Never commit these values to your repository
- The MATCH_PASSWORD should be strong and unique
- Rotate your API keys periodically
- Use repository secrets, not environment secrets, for better security