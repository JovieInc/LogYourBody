# Design System Deduplication Summary

## Overview
This document summarizes the deduplication and consolidation of SwiftUI components in the LogYourBody design system. All redundant components have been refactored to use generic base components while maintaining backward compatibility.

## New Base Components Created

### 1. BaseButton
**Location**: `/DesignSystem/Atoms/BaseButton.swift`

A highly configurable button component that consolidates all button variations:
- **Configuration Properties**:
  - `style`: Primary, secondary, tertiary, destructive, ghost, social, or custom
  - `size`: Small, medium, large, or custom dimensions
  - `isLoading`: Shows loading state with progress indicator
  - `isEnabled`: Controls enabled/disabled state
  - `fullWidth`: Makes button expand to full container width
  - `icon`: Optional SF Symbol with leading/trailing position
  - `hapticFeedback`: Configurable haptic feedback style

### 2. BaseTextField
**Location**: `/DesignSystem/Atoms/BaseTextField.swift`

A unified text input component supporting all field variations:
- **Configuration Properties**:
  - `style`: Default, outlined, underlined, or custom styling
  - `hasIcon`: Shows leading icon
  - `isSecure`: Password field with visibility toggle
  - `errorMessage`: Displays validation errors
  - `helperText`: Shows helper text below field
  - `characterLimit`: Enforces character limit with counter
  - Custom padding and corner radius

### 3. BaseIconButton
**Location**: `/DesignSystem/Atoms/BaseButton.swift`

A specialized icon-only button component:
- **Styles**: Filled, outlined, or plain
- Configurable size and haptic feedback
- Proper accessibility support

## Refactored Components (Now Legacy Wrappers)

### Button Components
1. **DSButton** → Uses `BaseButton`
   - Maintains original API for backward compatibility
   - Maps ButtonStyle and ButtonSize enums to BaseButton configuration

2. **DSAuthButton** → Uses `BaseButton`
   - Auth-specific styling preserved through custom configuration
   - Full-width by default with social login support

3. **StandardButton** → Uses `BaseButton`
   - All variants (primary, secondary, tertiary, destructive, ghost) mapped
   - Icon support maintained

4. **IconButton** → Uses `BaseIconButton`
   - Simplified to use base icon button with outlined style

5. **TextButton** → Uses `BaseButton`
   - Ghost style with custom sizing for text-only buttons

6. **SocialLoginButton** → Uses `BaseButton`
   - Provider-specific styling through custom configuration
   - Border overlay for certain providers

7. **LogoutButton** → Uses `BaseButton`
   - Custom red styling with system background

### TextField Components
1. **DSTextField** → Uses `BaseTextField`
   - Standard text field with default styling

2. **DSSecureField** → Uses `BaseTextField`
   - Password configuration with visibility toggle

3. **StandardTextField** → Could be refactored to use `BaseTextField`
   - Currently maintains its own implementation
   - Candidate for future consolidation

## Benefits Achieved

### 1. Code Reduction
- Eliminated ~500+ lines of duplicate button code
- Reduced text field implementations from 3 to 1 base component
- Centralized styling and behavior logic

### 2. Consistency
- All buttons now share the same interaction patterns
- Unified animation timing and easing curves
- Consistent haptic feedback across all interactive elements

### 3. Maintainability
- Single source of truth for button and text field behavior
- Easy to add new button styles without creating new components
- Simplified testing - test base components once

### 4. Flexibility
- Custom styling through configuration objects
- ViewBuilder support for complex button content
- Extensible design for future requirements

## Migration Guide

### For New Code
Use base components directly:
```swift
// Instead of: DSButton("Save", style: .primary, size: .medium) {}
BaseButton("Save", configuration: ButtonConfiguration(style: .primary)) {}

// Instead of: DSTextField(text: $email, placeholder: "Email")
BaseTextField(text: $email, placeholder: "Email", configuration: .email)
```

### For Existing Code
No changes required - all existing components continue to work as legacy wrappers.

## Component Hierarchy Alignment

### Atoms (Pure, Generic UI Elements)
- ✅ BaseButton
- ✅ BaseTextField
- ✅ BaseIconButton
- ✅ DSProgressBar
- ✅ DSCircularProgress
- ✅ DSLogo
- ✅ DSAvatar
- ✅ DSText
- ✅ DSTrendIndicator
- ✅ DSMetricLabel
- ✅ DSMetricValue

### Molecules (Small Reusable Groups)
- ✅ UserGreeting (uses atoms)
- ✅ StepsIndicator (uses atoms)
- ✅ SocialLoginButton (uses BaseButton)
- ✅ LogoutButton (uses BaseButton)

### Organisms (Larger Semantic Structures)
- ✅ MetricSummaryCard (replaces legacy MetricCard/CompactMetricCard)
- ✅ DashboardHeader (uses molecules + atoms)
- ✅ LoadingScreen (uses atoms)
- ✅ CoreMetricsRow (uses molecules)
- ✅ SecondaryMetricsRow (uses molecules)
- ✅ DashboardContent (uses organisms + molecules)

## Future Recommendations

1. **Complete StandardTextField Migration**: Refactor StandardTextField to use BaseTextField for full consolidation

2. **Create BaseCard Component**: Many components use card-like containers that could be standardized

3. **Extract Common Modifiers**: Create reusable view modifiers for common patterns like press animations

4. **Documentation**: Add comprehensive documentation to base components with usage examples

5. **Testing**: Create unit tests for base components to ensure reliability

## iOS Settings & Profile Deduplication

### Canonical Views

- **Settings screen**: `PreferencesView`
  - Location: `/Views/PreferencesView.swift`
  - Responsibilities:
    - Account details (email, logout, delete account)
    - Profile summary (name, DOB, height display only)
    - Measurement system and tracking goals
    - Integrations (Apple Health, resync)
    - Security & privacy (biometrics, password, sessions)
    - Subscription, photos, advanced, and danger sections
  - Entry points:
    - `DashboardHeaderCompact` avatar tap
    - `DashboardHeaderCompact` "Add age" and "Add height" chips

- **Profile editor**: `ProfileSettingsViewV2`
  - Location: `/Views/ProfileSettingsViewV2.swift`
  - Responsibilities:
    - Edit first/last name and consolidated display name
    - Edit date of birth, height (metric/imperial), and biological sex
    - Manage profile photo upload
    - Drive profile persistence via `AuthManager` + Core Data + Supabase
  - Presentation:
    - Presented as a sheet from `PreferencesView` when the user taps
      **Full name**, **Date of birth**, or **Height** in the Profile section.

### Removed / Legacy Implementations

- **Legacy `SettingsView`**
  - File: `Views/SettingsView.swift`
  - Status: Removed from the target and codebase; no remaining references.
  - Rationale: Duplicated the settings surface using an alternate atomic layout
    while `PreferencesView` remained the actual runtime entry point.

- **Inline profile edit sheets in `PreferencesView`**
  - Types removed:
    - `BirthdayEditSheet`
    - `HeightEditSheet`
  - Rationale: These were ad-hoc editors for DOB/height that duplicated logic
    now centralized in `ProfileSettingsViewV2` (via `DatePickerSheet` and
    `ProfileHeightPickerSheet`). All profile edits now go through the
    consolidated profile editor.

### Guidance for New Code

- Route **all** settings/profile navigation to `PreferencesView`.
- For any edits to name, DOB, height, or biological sex:
  - Present `ProfileSettingsViewV2` instead of introducing new sheets or
    inline editors.
- Do **not** reintroduce `SettingsView` or alternate settings/profile screens
  without explicitly deprecating and updating all entry points.
