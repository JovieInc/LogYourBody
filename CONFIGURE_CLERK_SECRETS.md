# Configure Clerk Secrets for CI/CD

## Important: Environment-Based Secrets

Your workflows use GitHub environments (dev, preview, production), so secrets must be added to **each environment** separately, not to the repository level.

## Required Secrets

The following secrets need to be added to EACH environment:

1. **NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY** - Your Clerk publishable key (starts with `pk_`)
2. **CLERK_SECRET_KEY** - Your Clerk secret key (starts with `sk_`)

## Steps to Configure

### 1. Get Your Clerk Keys

1. Go to [Clerk Dashboard](https://dashboard.clerk.com)
2. Sign in to your account
3. Select your application
4. Go to **API Keys** section
5. Copy both keys:
   - **Publishable key** (starts with `pk_test_` or `pk_live_`)
   - **Secret key** (starts with `sk_test_` or `sk_live_`)

### 2. Add Secrets to GitHub Environments

You need to add secrets to EACH environment that uses them:

#### For the `dev` environment:
1. Go to your repository: https://github.com/JovieInc/LogYourBody
2. Click on **Settings** tab
3. In the left sidebar, click **Environments**
4. Click on **dev**
5. Under **Environment secrets**, click **Add secret**
6. Add the first secret:
   - **Name**: `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
   - **Value**: Paste your publishable key (e.g., `pk_test_...`)
   - Click **Add secret**
7. Add the second secret:
   - **Name**: `CLERK_SECRET_KEY`
   - **Value**: Paste your secret key (e.g., `sk_test_...`)
   - Click **Add secret**

#### Repeat for other environments:
- Do the same for **preview** environment
- Do the same for **production** environment (use production keys `pk_live_` and `sk_live_`)

### 3. Optional: Environment-Specific Secrets

If you want different Clerk apps for different environments, you can also add:

- `DEV_CLERK_PUBLISHABLE_KEY` and `DEV_CLERK_SECRET_KEY`
- `PREVIEW_CLERK_PUBLISHABLE_KEY` and `PREVIEW_CLERK_SECRET_KEY`
- `PROD_CLERK_PUBLISHABLE_KEY` and `PROD_CLERK_SECRET_KEY`

Then update the workflows to use these environment-specific secrets.

### 4. Verify Configuration

After adding the secrets:

1. Make a small change to trigger CI
2. Check the Web Rapid Loop workflow
3. The build should now pass the Clerk validation

## Test Command

You can verify the secrets are configured by running:

```bash
gh secret list | grep CLERK
```

This should show:
```
CLERK_SECRET_KEY            2025-07-18T...
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY  2025-07-18T...
```

## Troubleshooting

If builds are still failing:

1. Ensure the keys are from the correct Clerk application
2. Check that you're using the right environment keys (test vs production)
3. Verify there are no extra spaces or characters in the secret values
4. For development, use `pk_test_` and `sk_test_` keys
5. For production, use `pk_live_` and `sk_live_` keys

## Security Notes

- Never commit these keys to your repository
- The publishable key is safe to expose in client-side code
- The secret key should NEVER be exposed to the client
- Rotate keys regularly for security