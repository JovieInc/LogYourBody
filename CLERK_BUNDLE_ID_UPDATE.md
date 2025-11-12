# Clerk Bundle ID Update Guide

**Date**: 2025-11-12
**Issue**: Authentication broken after bundle ID change from `LogYourBody.LogYourBody` to `com.logyourbody.app`

---

## 🔍 Problem

After updating the bundle ID to match RevenueCat (`com.logyourbody.app`), Clerk authentication stopped working because Clerk is configured for the old bundle ID.

---

## ✅ Solution: Update Clerk Dashboard

### Step 1: Log into Clerk Dashboard
1. Go to [https://dashboard.clerk.com](https://dashboard.clerk.com)
2. Select your LogYourBody application

### Step 2: Update iOS Settings
1. Navigate to **Settings** → **Mobile**
2. Find the **iOS** section
3. Look for **Bundle ID** or **iOS Bundle Identifier** field
4. Update it from:
   - **Old**: `LogYourBody.LogYourBody`
   - **New**: `com.logyourbody.app`
5. Click **Save**

### Step 3: Update Redirect URIs (if needed)
If you have custom redirect URIs configured:
1. Go to **Settings** → **Sessions** or **OAuth**
2. Update any redirect URIs that include the old bundle ID
3. Change from: `LogYourBody.LogYourBody://`
4. Change to: `com.logyourbody.app://` or keep using `logyourbody://` (URL scheme)

**Note**: The URL scheme (`logyourbody://`) in Info.plist doesn't need to match the bundle ID, so it can stay as is.

### Step 4: Update OAuth Settings
1. Go to **Settings** → **OAuth**
2. Check **Allowed Redirect URIs**
3. Ensure these patterns are allowed:
   ```
   logyourbody://*
   com.logyourbody.app://*
   ```

### Step 5: Test Authentication
1. Clean build in Xcode (⇧⌘K)
2. Rebuild and run
3. Try signing in with Apple ID
4. Verify authentication flow completes

---

## 🔄 Alternative: Revert Bundle ID (Not Recommended)

If you prefer to keep the old bundle ID and update RevenueCat instead:

### Revert Bundle ID
```bash
# In project.pbxproj, change back to:
PRODUCT_BUNDLE_IDENTIFIER = LogYourBody.LogYourBody;
```

### Update RevenueCat
1. Go to [RevenueCat Dashboard](https://app.revenuecat.com)
2. Navigate to your iOS app settings
3. Update Bundle ID from `com.logyourbody.app` to `LogYourBody.LogYourBody`
4. **Note**: This may require recreating products with new identifiers

**Why Not Recommended**:
- Old bundle ID doesn't follow Apple conventions
- Would need to recreate RevenueCat products
- Less professional for App Store

---

## 📋 Verification Checklist

After updating Clerk:

- [ ] Clerk dashboard shows bundle ID: `com.logyourbody.app`
- [ ] Clean build in Xcode (⇧⌘K)
- [ ] Rebuild app (⌘B)
- [ ] Run app (⌘R)
- [ ] Authentication flow works
- [ ] Sign in with Apple ID succeeds
- [ ] User can complete onboarding
- [ ] RevenueCat offerings load
- [ ] Paywall displays correctly

---

## 🔍 Troubleshooting

### Issue: "Invalid redirect URI"
**Fix**: Add `logyourbody://*` to Clerk's allowed redirect URIs

### Issue: "App not registered"
**Fix**: Ensure bundle ID in Clerk exactly matches: `com.logyourbody.app`

### Issue: Sign in opens browser but doesn't return to app
**Fix**: Verify URL scheme `logyourbody` is in Info.plist CFBundleURLSchemes

### Issue: "Domain not found" error
**Fix**: Check that CLERK_FRONTEND_API and CLERK_PUBLISHABLE_KEY are correct in Config.xcconfig

---

## 📝 Files Modified

The bundle ID change affected:
- `apps/ios/LogYourBody.xcodeproj/project.pbxproj` (Commit 4aeacbfa6)
  - Updated: `PRODUCT_BUNDLE_IDENTIFIER = com.logyourbody.app`

Files that DON'T need changes:
- ✅ `Info.plist` - URL scheme stays as `logyourbody`
- ✅ `Config.xcconfig` - Clerk keys stay the same
- ✅ `AuthManager.swift` - No code changes needed

---

## 🎯 What Needs to Change in Clerk

**Only this needs to change in Clerk dashboard:**
```
Old Bundle ID: LogYourBody.LogYourBody
New Bundle ID: com.logyourbody.app
```

Everything else (API keys, domains, frontend API, etc.) stays the same.

---

## 📚 Related Documentation

- [Clerk iOS SDK Docs](https://clerk.com/docs/quickstarts/ios)
- [Clerk Mobile Apps Guide](https://clerk.com/docs/deployments/mobile-apps)
- [Apple Bundle ID Guidelines](https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleidentifier)

---

**Once Clerk is updated, both authentication and RevenueCat will work with the correct bundle ID!**
