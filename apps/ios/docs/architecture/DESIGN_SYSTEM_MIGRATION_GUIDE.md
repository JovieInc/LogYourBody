# Design System Migration Guide

## Overview

This guide documents the migration from deprecated wrapper components and raw SwiftUI components to the atomic design system components (BaseButton and BaseTextField).

## Phase 2 Migration Summary

**Status**: ✅ Completed
**Date**: October 29, 2025
**Files Migrated**: 10 files (Tier 1 + Tier 2)

### Migrated Components

#### Tier 1: Auth Components (7 files)
- `AuthFormField.swift` - DSTextField/DSSecureField → BaseTextField
- `LoginForm.swift` - DSAuthButton → BaseButton
- `DSAuthDivider.swift` - Preview code updated to BaseButton
- `SignUpForm.swift` - DSAuthButton → BaseButton
- `VerificationForm.swift` - DSAuthButton → BaseButton
- `BiometricAuthView.swift` - DSAuthButton → BaseButton
- `ErrorStateView.swift` - DSButton → BaseButton

#### Tier 2: Critical Settings Views (3 files)
- `ChangePasswordView.swift` - Raw Button() → BaseButton
- `DeleteAccountView.swift` - Raw Button() → BaseButton
- `BulkPhotoImportView.swift` - 7 raw Button() instances → BaseButton

## Migration Patterns

### DSAuthButton → BaseButton

**Before:**
```swift
DSAuthButton(
    title: "Sign in",
    style: .primary,
    isLoading: isLoading,
    isEnabled: isFormValid,
    action: onLogin
)
```

**After:**
```swift
BaseButton(
    "Sign in",
    configuration: ButtonConfiguration(
        style: .custom(background: .white, foreground: .black),
        isLoading: isLoading,
        isEnabled: isFormValid,
        fullWidth: true
    ),
    action: onLogin
)
```

### DSButton → BaseButton

**Before:**
```swift
DSButton(
    title: "Try Again",
    style: .primary,
    size: .medium,
    action: buttonAction
)
```

**After:**
```swift
BaseButton(
    "Try Again",
    configuration: ButtonConfiguration(
        style: .custom(background: .white, foreground: .black),
        size: .medium
    ),
    action: buttonAction
)
```

### Raw Button() → BaseButton

**Before:**
```swift
Button(action: {
    performAction()
}) {
    Text("Submit")
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color.appPrimary)
        .cornerRadius(12)
}
.disabled(!isValid)
```

**After:**
```swift
BaseButton(
    "Submit",
    configuration: ButtonConfiguration(
        style: .custom(background: .appPrimary, foreground: .white),
        isEnabled: isValid,
        fullWidth: true
    ),
    action: {
        performAction()
    }
)
```

### DSTextField/DSSecureField → BaseTextField

**Before:**
```swift
VStack(alignment: .leading, spacing: 8) {
    Text(label)
        .font(.system(size: 14))
        .foregroundColor(.appTextSecondary)

    if isSecure {
        DSSecureField(
            text: $text,
            placeholder: placeholder
        )
    } else {
        DSTextField(
            text: $text,
            placeholder: placeholder,
            keyboardType: keyboardType
        )
    }
}
```

**After:**
```swift
VStack(alignment: .leading, spacing: 8) {
    Text(label)
        .font(.system(size: 14))
        .foregroundColor(.appTextSecondary)

    BaseTextField(
        text: $text,
        placeholder: placeholder,
        configuration: TextFieldConfiguration(
            isSecure: isSecure,
            showToggle: isSecure
        ),
        keyboardType: keyboardType,
        textContentType: textContentType,
        autocapitalization: autocapitalization
    )
}
```

## Common Button Styles

### Primary Auth Button (White on Dark)
```swift
ButtonConfiguration(
    style: .custom(background: .white, foreground: .black),
    fullWidth: true
)
```

### Primary Action Button (Brand Color)
```swift
ButtonConfiguration(
    style: .custom(background: .appPrimary, foreground: .white),
    fullWidth: true
)
```

### Destructive Button (Red)
```swift
ButtonConfiguration(
    style: .custom(background: .red, foreground: .white),
    fullWidth: true
)
```

### Secondary/Tertiary Button
```swift
ButtonConfiguration(
    style: .tertiary
)
```

### Button with Icon
```swift
ButtonConfiguration(
    style: .custom(background: .appPrimary, foreground: .white),
    fullWidth: true,
    icon: "square.and.arrow.down"
)
```

### Conditional Styling
```swift
ButtonConfiguration(
    style: isValid ? .custom(background: .appPrimary, foreground: .white) : .custom(background: .gray, foreground: .white),
    isEnabled: isValid,
    fullWidth: true
)
```

## ButtonConfiguration Options

```swift
ButtonConfiguration(
    style: ButtonStyleVariant,      // .primary, .secondary, .tertiary, .custom(background:foreground:)
    size: ButtonSize?,               // .small, .medium, .large
    isLoading: Bool?,                // Shows loading spinner
    isEnabled: Bool?,                // Enable/disable button
    fullWidth: Bool?,                // Expand to full width
    icon: String?,                   // SF Symbol name
    iconPosition: IconPosition?,     // .leading, .trailing
    hapticFeedback: HapticFeedback?  // Haptic feedback type
)
```

## TextFieldConfiguration Options

```swift
TextFieldConfiguration(
    style: TextFieldStyleVariant?,   // .standard, .outlined, .rounded
    icon: String?,                   // SF Symbol for leading icon
    isSecure: Bool?,                 // Secure text entry
    showToggle: Bool?,               // Show visibility toggle for secure fields
    errorMessage: String?,           // Error message to display
    helperText: String?,             // Helper text below field
    characterLimit: Int?             // Maximum character count
)
```

## Build Verification

All migrations have been verified with a successful build:
```bash
xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

**Result**: ✅ BUILD SUCCEEDED

## Remaining Work

The following files still use deprecated components or raw SwiftUI and should be migrated in future phases:

### Tier 3: Onboarding Flow (9 files)
- OnboardingContainerView.swift
- WelcomeStepView.swift
- HealthKitStepView.swift
- NotificationsStepView.swift
- ProfilePreparationView.swift
- NameInputView.swift
- DateOfBirthInputView.swift
- GenderInputView.swift
- HeightInputView.swift

### Tier 4: Remaining Views (15+ files)
- Various dashboard and settings views
- Photo capture and editing views
- Metric input views
- Other utility views

## Best Practices

1. **Always use BaseButton over raw Button()** - Ensures consistent styling and behavior
2. **Use ButtonConfiguration for customization** - More maintainable than inline styling
3. **Prefer predefined styles** - Use .primary, .secondary, .tertiary when possible
4. **Use .custom() for special cases** - When you need specific colors
5. **Always specify fullWidth for full-width buttons** - Don't rely on manual frame modifiers
6. **Use isLoading for async operations** - Built-in loading indicator support
7. **Use isEnabled instead of .disabled()** - More declarative approach

## Migration Checklist

When migrating a file:

- [ ] Read the file to understand current implementation
- [ ] Identify all button and text field instances
- [ ] Map deprecated components to atomic components
- [ ] Update with appropriate ButtonConfiguration or TextFieldConfiguration
- [ ] Preserve all existing functionality (loading states, validation, etc.)
- [ ] Remove any manual styling that's now handled by configuration
- [ ] Verify the file compiles without errors
- [ ] Test the functionality in the simulator if critical

## References

- [Atomic Design Guide](./AtomicDesignGuide.md)
- [BaseButton Implementation](../../LogYourBody/DesignSystem/Atoms/BaseButton.swift)
- [BaseTextField Implementation](../../LogYourBody/DesignSystem/Atoms/BaseTextField.swift)
- [Deprecated Components](../../LogYourBody/DesignSystem/Atoms/)

---

**Last Updated**: October 29, 2025
**Status**: Phase 2 Complete, Tiers 3-4 Pending
