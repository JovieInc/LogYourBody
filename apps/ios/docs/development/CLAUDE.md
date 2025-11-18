# LogYourBody iOS App - Development Guide

## Design System Guidelines

### ✅ General Recommendations (applies to all screens)

- **Typography**: Use a neutral, professional sans-serif like SF Pro (Apple's system font) or Inter. Avoid playful or round fonts.
- **Color palette**: Black, white, and neutral grayscale. Accent colors should be subtle and only for UX cues (e.g. progress dots, toggles, CTA states).
- **Backgrounds**: Use true black or near-black for OLED elegance, but ensure text and icons meet AA accessibility contrast.
- **Copywriting**: Short, confident, Apple-style tone. No fluff, every word earns its place. Capitalize sparingly.
- **Accessibility**: Ensure text isn't low contrast against Liquid Glass. Avoid pure white on pure black unless bold and large.

## Project Context

This is the LogYourBody iOS app, a fitness tracking application that helps users monitor their weight, body composition, and progress photos. The app integrates with HealthKit, uses Clerk for authentication, and syncs data with Supabase.

## Key Technical Decisions

- **Authentication**: Using Clerk SDK with browser-based OAuth flow for Apple Sign In
- **Design System**: iOS 26 Liquid Glass design with proper fallbacks for older iOS versions
- **Data Persistence**: Core Data for local storage, Supabase for cloud sync
- **Health Integration**: HealthKit for weight and step data synchronization

## Important Commands

When making code changes, always run the following lint and typecheck commands:
- Check for available scripts in package.json or similar configuration files
- Run appropriate linting commands for Swift/iOS development

## Swift Missing-File Rule

If the compiler reports that a referenced Swift file or type cannot be found, assume the reference is correct and the project setup needs to be updated. Follow these steps in order:

1. Ask the user to create the missing file and provide its complete contents.
2. If the file already exists, instruct the user to add it to the correct Xcode target/group.
3. Only as a last resort, resolve import, module, or path configuration issues.

Never “fix” this by swapping to legacy classes (for example `DashboardOld.swift`), commenting out or removing the new feature, or reverting without explicit user approval. If reverting truly seems like the only option, check with the user first.