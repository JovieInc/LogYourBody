# Match Setup Instructions

Since Match requires interactive mode for initial setup, please run these commands manually in your terminal.

## Prerequisites

1. **Create a GitHub Personal Access Token**:
   - Go to https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Give it a name like "Match Access"
   - Select the `repo` scope
   - Generate and copy the token

2. **Create the base64 auth string**:
   ```bash
   echo -n "itstimwhite:YOUR_GITHUB_PAT" | base64
   ```
   Copy this value for later.

## Option 1: Start Fresh (Recommended)

Since we're having password issues, let's completely start over:

1. **Delete the certificates repository on GitHub**:
   - Go to https://github.com/itstimwhite/certificates
   - Settings → Delete this repository

2. **Create a new empty repository**:
   - Create a new PRIVATE repository named `certificates`
   - Don't add any files (no README, .gitignore, etc.)

3. **Set up environment variables**:
   ```bash
   cd /Users/timwhite/Documents/GitHub/TBF/LogYourBody/apps/ios
   export MATCH_PASSWORD="Xuwa8gLaHbj3UCC3eC7M"
   export MATCH_GIT_URL="https://github.com/itstimwhite/certificates.git"
   export MATCH_GIT_BASIC_AUTHORIZATION="YOUR_BASE64_AUTH_STRING"
   export APP_STORE_CONNECT_API_KEY_PATH="$(pwd)/fastlane/api_key.json"
   ```

4. **Initialize Match**:
   ```bash
   bundle exec fastlane match init
   ```
   - Choose option 1 (git)
   - Enter the git URL when prompted

5. **Create App Store certificates and profiles**:
   ```bash
   bundle exec fastlane match appstore
   ```

6. **Create Development certificates and profiles**:
   ```bash
   bundle exec fastlane match development
   ```

## Option 2: Fix Existing Setup

If you want to keep the existing certificates repo:

1. **Clone the repo locally** (outside this project):
   ```bash
   cd ~/Desktop
   git clone https://github.com/itstimwhite/certificates.git
   cd certificates
   ```

2. **Check if there are encrypted files**:
   ```bash
   ls -la
   find . -name "*.cer" -o -name "*.p12" -o -name "*.mobileprovision"
   ```

3. **If there are files, try the old password or change it**:
   ```bash
   # Go back to the iOS project
   cd /Users/timwhite/Documents/GitHub/TBF/LogYourBody/apps/ios
   
   # Try to decrypt with potential passwords
   export MATCH_PASSWORD="[try different passwords]"
   bundle exec fastlane match appstore --readonly
   ```

4. **If you can't decrypt, nuke and start fresh**:
   ```bash
   # This will delete ALL certificates and profiles
   bundle exec fastlane match nuke distribution
   bundle exec fastlane match nuke development
   
   # Then recreate with new password
   export MATCH_PASSWORD="Xuwa8gLaHbj3UCC3eC7M"
   bundle exec fastlane match appstore
   bundle exec fastlane match development
   ```

## After Setup

1. **Update GitHub Secrets**:
   - `MATCH_PASSWORD`: Use the password you set
   - `MATCH_GIT_BASIC_AUTHORIZATION`: The base64 auth string you created

2. **Test locally**:
   ```bash
   bundle exec fastlane setup_provisioning
   ```

3. **Commit any changes** to the certificates repo.

## Troubleshooting

- If you get "Invalid password" errors, the repo has existing encrypted content
- If you get authentication errors, check your GitHub PAT and base64 encoding
- If Match can't find profiles, ensure your App ID has all required capabilities enabled

The key is that Match needs to run interactively the first time to set up the encryption password.