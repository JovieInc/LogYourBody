thes# GitHub Actions Secrets for iOS CI/CD with Match

Set up these secrets in your GitHub repository settings:

## Required Secrets

### 1. App Store Connect API Key
- **Secret Name**: `APP_STORE_CONNECT_API_KEY`
- **Value**: The contents of your private key (-----BEGIN PRIVATE KEY-----...-----END PRIVATE KEY-----)
- **How to get**: From your api_key.json file, copy just the key content

### 2. App Store Connect API Key ID
- **Secret Name**: `APP_STORE_CONNECT_API_KEY_ID`
- **Value**: V9NW6ZGUK3

### 3. App Store Connect API Issuer ID
- **Secret Name**: `APP_STORE_CONNECT_API_ISSUER_ID`
- **Value**: c195f569-ff16-40fa-aaff-4fe94e8139ad

### 4. Match Password
- **Secret Name**: `MATCH_PASSWORD`
- **Value**: Your Match encryption password (the new one you just set)

### 5. Match Git URL (Optional - can be in workflow)
- **Secret Name**: `MATCH_GIT_URL`
- **Value**: https://github.com/itstimwhite/certificates.git

### 6. Apple Team ID
- **Secret Name**: `APPLE_TEAM_ID`
- **Value**: 6P36X5723P

### 7. App Store App ID
- **Secret Name**: `APP_STORE_APP_ID`
- **Value**: 6470661673

### 8. Match Git Basic Authorization (for private repository)
- **Secret Name**: `MATCH_GIT_BASIC_AUTHORIZATION`
- **Value**: Base64 encoded "username:personal_access_token"
- **Notes**:
- - The GitHub personal access token must include the **repo** scope (read & write) so that Match can clone and push certificates and provisioning profiles when creating or renewing them.
- - Insufficient permissions will result in clone or push failures during CI.
- **How to create**: 
  1. Get your GitHub username (e.g., `itstimwhite`)
  2. Create a GitHub Personal Access Token:
     - Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
     - Click "Generate new token" (classic)
     - Give it a descriptive name like "Match Certificates Access"
     - Select the `repo` scope (Full control of private repositories)
     - Set expiration (recommend 90 days and rotate regularly)
     - Click "Generate token"
     - Copy the token value (starts with `ghp_` or `github_pat_`)
  3. Encode your credentials:
     ```bash
     echo -n "your-github-username:your-personal-access-token" | base64
     ```
     For example:
     ```bash
     echo -n "itstimwhite:github_pat_11AILQMSY0..." | base64
     ```
  4. Use the base64 output as the secret value

**Important**: The token needs `repo` scope because Match needs to:
- Clone the private certificates repository
- Read existing certificates and profiles
- Push new certificates when they're created/renewed
- Access all repository contents (certificates are stored encrypted)

## Setting Up Secrets

1. Go to your repository on GitHub
2. Navigate to Settings > Secrets and variables > Actions
3. Click "New repository secret"
4. Add each secret with the name and value listed above

## Notes

- The API key should be the raw private key content, not base64 encoded
- Make sure there are no extra spaces or newlines when copying values
- The Match password should be the one you just changed to

## Initial Certificate Setup

The first time you set up Match, you need to create the certificates locally:

1. Clone this repository locally
2. Navigate to the iOS directory:
   ```bash
   cd apps/ios
   ```

3. Set up environment variables:
   ```bash
   export MATCH_GIT_URL='https://github.com/itstimwhite/certificates.git'
   export MATCH_PASSWORD='your-secure-password'
   export MATCH_READONLY=false
   export APP_STORE_CONNECT_API_KEY_ID='V9NW6ZGUK3'
   export APP_STORE_CONNECT_API_ISSUER_ID='c195f569-ff16-40fa-aaff-4fe94e8139ad'
   export APP_STORE_CONNECT_API_KEY='-----BEGIN PRIVATE KEY-----
   ... your key content ...
   -----END PRIVATE KEY-----'
   export APPLE_TEAM_ID='6P36X5723P'
   ```

4. Create the certificates and provisioning profiles:
   ```bash
   bundle install
   bundle exec fastlane setup_provisioning type:appstore
   ```

5. Commit and push the changes to your certificates repository

## Troubleshooting

### OpenSSL Curve Name Error
If you encounter "invalid curve name" errors on GitHub Actions, the setup_provisioning lane includes error handling for this. The API key setup is handled in the Fastfile rather than through Match directly to work around OpenSSL compatibility issues.

### No Code Signing Identity Found
This error occurs when the certificates repository is empty. You must run the "Initial Certificate Setup" steps above locally first to create the certificates. GitHub Actions runs in readonly mode by default and cannot create new certificates.
