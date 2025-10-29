# LogYourBody Widget Setup Instructions

The widget files have been created. To add the widget to your Xcode project:

## 1. Add Widget Extension in Xcode

1. Open `LogYourBody.xcodeproj` in Xcode
2. Select File → New → Target
3. Choose "Widget Extension"
4. Configure:
   - Product Name: `LogYourBodyWidget`
   - Team: Select your development team
cl   - Organization Identifier: Same as main app
   - Language: Swift
   - Include Configuration Intent: NO
   - Project: LogYourBody
   - Embed in Application: LogYourBody

## 2. Replace Widget Files

1. Delete the auto-generated files in the widget target
2. Add the created files to the widget target:
   - `LogYourBodyWidget/LogYourBodyWidget.swift`
   - `LogYourBodyWidget/Info.plist`
   - `LogYourBodyWidget/LogYourBodyWidget.entitlements`

## 3. Configure Widget Target

1. Select the LogYourBodyWidget target
2. Go to Signing & Capabilities
3. Ensure App Groups capability is added with `group.com.logyourbody.shared`
4. Set deployment target to match main app (iOS 17.0+)

## 4. Update Main App

The following files have been updated:
- `LogYourBodyApp.swift` - Added widget data manager and deep link handling
- `AddEntrySheet.swift` - Added widget data updates when saving metrics
- `Services/WidgetDataManager.swift` - New service for managing widget data
- `LogYourBody.entitlements` - Added app group

## 5. Configure URL Scheme

The URL scheme `logyourbody://` is already configured in Info.plist

## 6. Test the Widget

1. Build and run the main app first
2. Add some weight and body fat data
3. Add the widget to your home screen
4. Test deep links by tapping on the widget

## Widget Features

- **Small Widget**: Shows three rings for weight, body fat %, and step count
- **Medium Widget**: Shows rings plus quick action buttons
- **Deep Links**:
  - `logyourbody://log` - Opens add entry sheet
  - `logyourbody://log/weight` - Opens weight entry
  - `logyourbody://log/bodyfat` - Opens body fat entry
  - `logyourbody://log/photo` - Opens photo entry

## Data Sharing

The widget shares data with the main app using:
- UserDefaults with app group `group.com.logyourbody.shared`
- Keys: `widget.latestWeight`, `widget.latestBodyFat`, `widget.todaySteps`

The widget automatically updates:
- When the app enters background
- When metrics are saved
- Every 30 minutes while app is active
- Every hour via timeline refresh