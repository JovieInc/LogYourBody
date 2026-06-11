# iOS Widget Extension Provisioning Plan

LogYourBody does not currently ship a Widget Extension target. The previous
widget scaffolding was retired because it created signing and release risk while
no widget binary was being shipped.

This document is the preflight checklist for restoring widget and Control Center
surfaces for Jovie issue #10364. Do not add WidgetKit source files, app-group
refresh timers, or widget build phases until the provisioning items below are
true.

## Current Status

- Main app bundle ID: `com.logyourbody.app`.
- Main app team ID: `G24T327LXT`.
- Main app App Group: `group.com.logyourbody.shared`.
- Current release profile: `match AppStore com.logyourbody.app 1780400349`.
- Widget Extension target: not present in `apps/ios/LogYourBody.xcodeproj`.
- Widget refresh scaffolding: intentionally absent; see
  `apps/ios/docs/setup/WIDGET_SETUP.md`.
- Safe slice already landed: body metrics are indexed in Core Spotlight from the
  app target.

## Required Decisions

Before adding a widget target, the release owner must choose and provision a
stable widget bundle ID. The recommended value is:

```text
com.logyourbody.app.widget
```

Use a specific widget App Store profile rather than a wildcard profile for the
first restored release. A specific profile makes CI failures easier to diagnose
and avoids accidentally broadening signing coverage for unrelated bundles.

## Provisioning Checklist

1. Create the Widget Extension app identifier in Apple Developer Portal:
   `com.logyourbody.app.widget`.
2. Enable the same App Group on the widget identifier:
   `group.com.logyourbody.shared`.
3. Create or update the App Store distribution profile for the widget bundle.
4. Install the profile through the existing release credential path.
5. Add the widget profile name to CI secrets or Fastlane match configuration.
6. Update the Xcode project with a real Widget Extension target.
7. Verify archive signing includes both the main app and widget extension.

## Implementation Boundaries

When the target exists and signs successfully, the product work can add:

- An `AppIntentConfiguration` widget for latest weight, body fat, or steps.
- A Control Center control that opens the existing quick-log weight flow.
- App Group data sharing for the latest local body metrics.
- Device or simulator screenshots proving widget configuration and control
  surfaces.

Do not reintroduce `WidgetDataManager` background timers in the main app target.
Widget state should be written only when the underlying body metric changes or
when the app explicitly refreshes shared widget data.

## Validation Before PR Merge

Run from `apps/ios` after the widget target is added:

```bash
swiftlint lint --strict
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build-for-testing
bundle exec fastlane ios validate_release
```

Release-ready evidence must include an archive or release-loop run that signs
both targets, plus screenshots for widget configuration and the Control Center
surface. Do not close #10364 until that evidence is attached.
