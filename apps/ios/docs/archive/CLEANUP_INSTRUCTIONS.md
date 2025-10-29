# Xcode Project Cleanup Instructions

## Files to Remove

The following files are empty and should be removed from the Xcode project:

1. **SupabaseClient.swift** (empty file)
2. **SupabaseManager.swift** (empty file)  
3. **Package.swift** (empty file in ios-native root)
4. **Package.resolved** (if exists)

## Steps to Clean Up

### 1. Run the Cleanup Script
```bash
cd /Users/timwhite/Documents/GitHub/TBF/LogYourBody/ios-native
chmod +x cleanup_xcode.sh
./cleanup_xcode.sh
```

### 2. In Xcode
1. Open the project in Xcode
2. In the Project Navigator (left sidebar), look for files with red names (missing files)
3. Right-click each red file and select "Delete"
4. Choose "Remove Reference" (not "Move to Trash" since files are already deleted)

### 3. Clean and Rebuild
1. Clean Build Folder: `Cmd + Shift + K`
2. Build: `Cmd + B`

## Current Project Structure

After cleanup, your Services folder should contain:
- ✅ AuthManager.swift (handles Clerk authentication)
- ✅ ClerkClient.swift (Clerk API client)
- ✅ CoreDataManager.swift (local data storage)
- ✅ HealthKitManager.swift (HealthKit integration)
- ✅ LoadingManager.swift (app loading state)
- ✅ SupabaseDataClient.swift (Supabase data operations)
- ✅ SyncManager.swift (data synchronization)

## Authentication Setup

The app now uses:
- **Clerk** for authentication (login, signup, sessions)
- **Supabase** for data storage only (user profiles, metrics)

## Known Issues Fixed

1. Removed duplicate Supabase client implementations
2. Removed empty Package.swift that was causing confusion
3. Consolidated authentication to use Clerk only