# Fix Duplicate Files in Xcode Project

## Issue
The Xcode project has duplicate file references causing build warnings. While this doesn't prevent the build, it should be cleaned up.

## Duplicate Files Found

The following files are referenced multiple times in the project:
- DietPhaseHistoryView.swift (mentioned 2 times)
- AppVersion.swift (3 times)
- BulkImportManager.swift (4 times)
- BulkPhotoImportView.swift (4 times)
- CompletionStepView.swift (4 times)
- And many others...

## How to Fix

### Option 1: Clean in Xcode (Recommended)
1. Open `LogYourBody.xcodeproj` in Xcode
2. In the navigator, look for files with duplicate entries
3. For each duplicate:
   - Select one of the duplicates
   - Press Delete (remove reference only, don't move to trash)
   - Ensure the file is still in the project once

### Option 2: Use Clean Build
For now, the build still works despite the warnings. The rapid loop deployment continues after the warning.

## Root Cause
This typically happens when:
- Files are added via drag & drop multiple times
- Merging branches with conflicting project file changes
- Moving files around in the project structure

## Prevention
- Always check for existing files before adding
- Use Xcode's "Add Files" dialog carefully
- Review project file changes in git before committing