# Atomic Design System Guide

## Overview

This guide documents the atomic design structure for the LogYourBody iOS app. The design system follows Brad Frost's Atomic Design methodology, organizing UI components into atoms, molecules, organisms, templates, and pages.

## Design System Structure

```
DesignSystem/
├── Theme.swift                    # Core theme definitions
├── DesignSystem.swift            # Main design system namespace
├── Atoms/                        # Basic building blocks
│   ├── Badge.swift
│   └── Divider.swift
├── Molecules/                    # Simple component combinations
│   ├── UserAvatar.swift
│   ├── DeveloperTapIndicator.swift
│   └── LogoutButton.swift
├── Organisms/                    # Complex component groups
│   ├── UserHeaderSection.swift
│   ├── SettingsSectionGroup.swift
│   └── DeveloperMenuSection.swift
└── Components/                   # Existing components
    ├── StandardButton.swift
    ├── StandardCard.swift
    ├── StandardTextField.swift
    └── SettingsRow.swift
```

## Component Hierarchy

### Atoms
The smallest building blocks of our design system:

- **Colors**: Defined in `Theme.swift` via `ColorTheme`
- **Typography**: Defined in `Theme.swift` via `TypographyTheme`
- **Spacing**: Defined in `Theme.swift` via `SpacingTheme`
- **Radius**: Defined in `Theme.swift` via `RadiusTheme`
- **DSDivider**: Custom divider with inset support
- **DSBadge**: Badge component with multiple styles

### Molecules
Simple combinations of atoms:

- **UserAvatar**: Circular avatar with initials
- **UserAvatarWithInfo**: Avatar combined with name/email text
- **DeveloperTapIndicator**: Progress indicator for developer menu unlock
- **LogoutButton**: Styled logout button with icon
- **CompactLogoutButton**: Minimal logout button variant

### Organisms
Complex, self-contained components:

- **UserHeaderSection**: Complete user profile header
- **SettingsSectionGroup**: Groups multiple settings sections
- **DeveloperMenuSection**: Developer options entry point
- **DeveloperTapHandler**: Handles tap counting logic
- **DeveloperToolsList**: List of developer tools

## Usage Examples

### Using Atoms

```swift
// Colors
Text("Hello")
    .foregroundColor(DesignSystem.colors.primary)

// Typography
Text("Title")
    .font(DesignSystem.typography.headlineLarge)

// Spacing
VStack(spacing: DesignSystem.spacing.md) {
    // Content
}

// Custom Divider
DSDivider()
    .insetted(16)
    .colored(.red)

// Badge
DSBadge("7", style: .number)
```

### Using Molecules

```swift
// User Avatar
UserAvatar(
    name: "John Doe",
    email: "john@example.com",
    size: .large,
    showBorder: true
)

// Developer Tap Indicator
DeveloperTapIndicator(remainingTaps: 3)

// Logout Button
LogoutButton {
    // Handle logout
}
```

### Using Organisms

```swift
// User Header
UserHeaderSection(
    name: user.name,
    email: user.email
)

// Settings Section
SettingsSection(header: "Profile") {
    SettingsRow(
        icon: "person",
        title: "Edit Profile",
        showChevron: true
    )
}

// Developer Menu
DeveloperMenuSection(
    isVisible: showDeveloper,
    onNavigate: { /* Navigate */ }
)
```

## Migration Guide

To migrate from the old SettingsView to the atomic version:

1. Replace color literals with `DesignSystem.colors.*`
2. Replace font definitions with `DesignSystem.typography.*`
3. Replace spacing values with `DesignSystem.spacing.*`
4. Replace custom dividers with `DSDivider()`
5. Extract repeated patterns into molecules/organisms

### Before:
```swift
Color.appBackground
.font(.system(size: 16))
.padding(20)
Divider().padding(.leading, 16)
```

### After:
```swift
DesignSystem.colors.background
.font(DesignSystem.typography.bodyMedium)
.padding(DesignSystem.spacing.lg)
DSDivider().insetted(16)
```

## Best Practices

1. **Use Theme Values**: Always use theme values instead of hardcoded colors/fonts
2. **Compose Components**: Build complex UI by composing smaller components
3. **Maintain Consistency**: Use existing components before creating new ones
4. **Document Variants**: Document all component variants and their use cases
5. **Test Accessibility**: Ensure all components are accessible

## Component Creation Guidelines

When creating new components:

1. **Identify the Level**: Determine if it's an atom, molecule, or organism
2. **Check Existing**: See if similar components exist
3. **Follow Naming**: Use descriptive names (e.g., `UserAvatar`, not `Avatar`)
4. **Add Preview**: Include SwiftUI previews showing all variants
5. **Document Usage**: Add comments explaining when to use the component

## Theme Extension

To add new theme values:

1. Update the appropriate theme struct in `Theme.swift`
2. Add the value to `DefaultTheme`
3. Update `DesignSystem` convenience accessors
4. Document the new value in this guide

## Future Enhancements

- [ ] Add animation atoms
- [ ] Create form templates
- [ ] Add more badge variants
- [ ] Create notification molecules
- [ ] Add skeleton loading states
- [ ] Create onboarding templates