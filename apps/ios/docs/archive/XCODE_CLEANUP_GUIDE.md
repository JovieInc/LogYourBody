# Xcode Cleanup Guide

## 🔧 Manual Cleanup Steps in Xcode

### 1. Remove Duplicate Config.xcconfig
- In Project Navigator, find `Config.xcconfig`
- If it appears twice, remove the one inside LogYourBody folder
- Keep the one at the root level

### 2. Remove Empty Files
Remove references to these empty files:
- SupabaseClient.swift (if it shows as 0 bytes)
- SupabaseManager.swift (if it shows as 0 bytes)
- Package.swift

### 3. Fix "Multiple Commands Produce" Error
1. Select your project in the navigator
2. Select the LogYourBody target
3. Go to Build Phases → Copy Bundle Resources
4. Look for duplicate entries (files listed twice)
5. Remove duplicates by selecting and clicking the minus button

### 4. Check Target Membership
For each Swift file:
1. Select the file
2. Open File Inspector (right panel)
3. Under "Target Membership", ensure only "LogYourBody" is checked

### 5. Clean File References
1. Look for red files (missing references)
2. Right-click → Delete → Remove Reference
3. If needed, re-add the file from its actual location

### 6. Final Build
1. Clean: `Cmd + Shift + K`
2. Build: `Cmd + B`

## ✅ Your Clean Project Structure

```
LogYourBody/
├── Services/
│   ├── AuthManager.swift         ✓ Clerk authentication
│   ├── ClerkClient.swift         ✓ Clerk API client
│   ├── CoreDataManager.swift     ✓ Local storage
│   ├── HealthKitManager.swift    ✓ Health data
│   ├── LoadingManager.swift      ✓ App loading
│   ├── SupabaseDataClient.swift  ✓ Cloud storage
│   └── SyncManager.swift         ✓ Data sync
├── Views/
│   ├── LoginView.swift
│   ├── SignUpView.swift
│   ├── EmailVerificationView.swift
│   └── [other views]
├── Models/
│   └── [data models]
└── Utils/
    └── Constants.swift
```
