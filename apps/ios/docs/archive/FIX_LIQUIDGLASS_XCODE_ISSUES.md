# Fix LiquidGlass Xcode Build Issues

## Problem
Xcode is showing "Build input files cannot be found" errors for files that have been deleted. The project file still contains references to the old LiquidGlass component files.

## Solution Steps

1. **Open Xcode Project**
   - Open LogYourBody.xcodeproj in Xcode

2. **Remove Missing File References**
   - In the Project Navigator (left sidebar), look for files with red text:
     - `LiquidGlassBackground.swift` (if shown in red)
     - `LiquidGlassAccent.swift` (if shown in red)
   - Right-click each red file and select "Delete"
   - Choose "Remove Reference" (not "Move to Trash" since files are already deleted)

3. **Add the Consolidated Component File**
   - Right-click on the "Utils" folder
   - Select "Add Files to LogYourBody..."
   - Navigate to `LogYourBody/Utils/`
   - Select `LiquidGlassComponents.swift`
   - Ensure "LogYourBody" target is checked
   - Click "Add"

4. **Clean Build Folder**
   - Menu: Product → Clean Build Folder (⇧⌘K)
   - Or: Hold Option key, then Product → Clean Build Folder

5. **Rebuild Project**
   - Build the project (⌘B)

## Alternative Solution (if above doesn't work)

If the files are not visible in Xcode but still causing errors:

1. Close Xcode
2. Open Terminal and run:
   ```bash
   cd /Users/timwhite/Documents/GitHub/TBF/LogYourBody/apps/ios
   rm -rf ~/Library/Developer/Xcode/DerivedData/LogYourBody-*
   ```
3. Reopen Xcode and rebuild

## Verify Success
After following these steps, you should have:
- ✅ No "Build input files cannot be found" errors
- ✅ No "Invalid redeclaration" errors
- ✅ Only `LiquidGlassComponents.swift` in the Utils folder
- ✅ Successful build

## Note
The consolidated `LiquidGlassComponents.swift` file contains all three components:
- LiquidGlassBackground
- LiquidGlassAccent  
- LiquidGlassButton

These are all defined in a single file to avoid duplication issues.