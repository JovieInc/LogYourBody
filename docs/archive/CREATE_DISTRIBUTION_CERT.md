# Creating Apple Distribution Certificate

## Step 1: Create Certificate Signing Request (CSR)

1. Open **Keychain Access** (Spotlight → "Keychain Access")
2. Menu: Keychain Access → Certificate Assistant → **Request a Certificate From a Certificate Authority**
3. Fill in:
   - User Email Address: Your Apple ID email
   - Common Name: Your name or company name
   - CA Email Address: Leave blank
   - Choose: "Saved to disk"
4. Save as `CertificateSigningRequest.certSigningRequest`

## Step 2: Create Certificate in Apple Developer

1. Go to https://developer.apple.com
2. Sign in with your Apple ID
3. Go to **Certificates, IDs & Profiles**
4. Click **Certificates** → **+** (Create a new certificate)
5. Select **Apple Distribution** (for App Store and Ad Hoc)
6. Click Continue
7. Upload your CSR file
8. Download the certificate (will be named `distribution.cer`)

## Step 3: Install & Export Certificate

1. Double-click the downloaded `distribution.cer` to install in Keychain
2. Open **Keychain Access**
3. Go to "My Certificates" category
4. Find "Apple Distribution: [Your Name]"
5. Click the arrow to confirm it has a private key
6. Right-click → **Export "Apple Distribution: ..."**
7. Save as `distribution.p12`
8. Set a strong password (you'll need this)

## Step 4: Verify You Have Everything

After these steps, you should have:

- ✅ `distribution.p12` - Your certificate with private key
- ✅ Password for the .p12 file
- ✅ `Github_CI_App_Store.mobileprovision` - Already have this
- ✅ `AuthKey_A76CPV6UUL.p8` - Already configured

Then we can add them to GitHub!
