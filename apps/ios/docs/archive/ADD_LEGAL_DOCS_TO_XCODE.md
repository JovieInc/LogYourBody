# Adding Legal Documents to Xcode

## Overview
The legal documents (Privacy Policy, Terms of Service, and Health Disclosure) need to be added to the Xcode project so they can be bundled with the app and displayed in-app.

## Steps to Add Legal Documents

1. **Open the Xcode Project**
   - Open `LogYourBody.xcodeproj` in Xcode

2. **Add the Legal Documents Folder**
   - In the Project Navigator (left sidebar), right-click on the `LogYourBody` folder
   - Select "Add Files to 'LogYourBody'..."
   - Navigate to `LogYourBody/Resources/Legal/`
   - Select the `Legal` folder
   - Make sure these options are checked:
     - ✅ Copy items if needed (if not already in the project folder)
     - ✅ Create folder references
     - ✅ Add to target: LogYourBody
   - Click "Add"

3. **Verify the Files**
   The following files should now appear in your project:
   - `Resources/Legal/privacy-policy.md`
   - `Resources/Legal/terms-of-service.md`
   - `Resources/Legal/health-disclosure.md`

4. **Add the LegalDocumentView.swift**
   - Right-click on the `Views` folder
   - Select "Add Files to 'LogYourBody'..."
   - Navigate to and select `LegalDocumentView.swift`
   - Make sure these options are checked:
     - ✅ Copy items if needed
     - ✅ Add to target: LogYourBody
   - Click "Add"

5. **Build and Test**
   - Build the project (⌘+B)
   - Run the app and navigate to Settings
   - Test that all three legal documents display correctly:
     - Health Disclaimer
     - Privacy Policy
     - Terms of Service

## File Structure
After adding, your project structure should include:
```
LogYourBody/
├── Views/
│   ├── SettingsView.swift (already updated)
│   ├── LegalDocumentView.swift (new)
│   └── ...
├── Resources/
│   └── Legal/
│       ├── privacy-policy.md
│       ├── terms-of-service.md
│       └── health-disclosure.md
└── ...
```

## Updating Legal Documents
When legal documents need to be updated:
1. Update the files in `/shared/legal/`
2. Run the copy script: `./copy-legal-docs.sh`
3. Build and deploy the app update

## Troubleshooting
- If documents don't load, check that the `.md` files are included in the app bundle (Build Phases > Copy Bundle Resources)
- Ensure the files are added to the correct target
- Check that file names match exactly (case-sensitive)