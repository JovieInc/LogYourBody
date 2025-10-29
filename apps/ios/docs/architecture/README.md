# LogYourBody Design System

A comprehensive design system for the LogYourBody iOS app, following Apple's Human Interface Guidelines and SwiftUI best practices.

## Overview

This design system provides a consistent, reusable, and scalable foundation for building the LogYourBody app's user interface. All components are built with SwiftUI and support dark mode by default.

## Structure

```
DesignSystem/
├── Theme.swift                 # Core theme system
├── Components/
│   ├── StandardButton.swift    # Button components
│   ├── StandardCard.swift      # Card and container components
│   ├── StandardTextField.swift # Text input components
│   ├── StandardHeader.swift    # Navigation header components
│   ├── SettingsRow.swift       # List and settings components
│   └── StateViews.swift        # Loading, empty, and error states
└── Modifiers/
    └── CommonModifiers.swift   # Reusable view modifiers

```

## Theme System

The theme system provides semantic colors, typography, spacing, and animations.

### Usage

```swift
struct MyView: View {
    @Environment(\.theme) var theme
    
    var body: some View {
        Text("Hello")
            .font(theme.typography.headlineMedium)
            .foregroundColor(theme.colors.text)
            .padding(theme.spacing.md)
    }
}
```

### Color Palette

- **Background**: `#111111` (near-black)
- **Surface**: `#1A1A1A` (cards and containers)
- **Primary**: `#5B63D3` (purple accent)
- **Text**: Primary, secondary, tertiary, quaternary variants
- **States**: Success, warning, error, info

### Typography Scale

- **Display**: Large (48pt), Medium (36pt), Small (32pt)
- **Headline**: Large (28pt), Medium (24pt), Small (20pt)
- **Body**: Large (18pt), Medium (16pt), Small (14pt)
- **Label**: Large (16pt), Medium (14pt), Small (12pt)
- **Caption**: Large (13pt), Medium (12pt), Small (11pt)

### Spacing Tokens

- `xxxs`: 2pt
- `xxs`: 4pt
- `xs`: 8pt
- `sm`: 12pt
- `md`: 16pt
- `lg`: 24pt
- `xl`: 32pt
- `xxl`: 48pt
- `xxxl`: 64pt

## Components

### Buttons

```swift
// Primary button
StandardButton("Get Started", style: .primary) {
    // Action
}

// Secondary button with icon
StandardButton("Upload", icon: "arrow.up", style: .secondary) {
    // Action
}

// Icon button
IconButton(icon: "plus") {
    // Action
}

// Text button
TextButton("Forgot password?") {
    // Action
}
```

### Cards

```swift
// Standard card
StandardCard {
    Text("Card content")
}

// Metric card
MetricCard(
    value: "72.5",
    label: "Weight (kg)",
    icon: "scalemass",
    trend: .down(2.3)
)

// Info card
InfoCard(
    icon: "lightbulb.fill",
    iconColor: .yellow,
    title: "Pro Tip",
    description: "Track measurements at the same time daily"
)
```

### Text Fields

```swift
// Standard text field
StandardTextField(
    text: $email,
    placeholder: "Enter email",
    label: "Email",
    icon: "envelope",
    keyboardType: .emailAddress,
    textContentType: .emailAddress
)

// Search field
SearchField(text: $searchText)

// Text area
TextArea(
    text: $bio,
    placeholder: "Tell us about yourself",
    label: "Bio",
    characterLimit: 500
)
```

### Headers

```swift
// Standard header
StandardHeader(
    title: "Profile",
    subtitle: "Manage your account",
    trailingItems: [
        HeaderAction(icon: "bell", badge: 3) { }
    ]
)

// Large header
StandardHeader(
    title: "Dashboard",
    style: .large
)

// Progress header
ProgressHeader(
    title: "Complete Profile",
    progress: 0.7
)
```

### Settings & Lists

```swift
// Settings section
SettingsSection(title: "Preferences") {
    SettingsRow(
        icon: "moon",
        title: "Dark Mode",
        type: .toggle(isOn: $darkMode)
    )
    
    SettingsRow(
        icon: "bell",
        title: "Notifications",
        subtitle: "Manage preferences",
        type: .navigation
    ) {
        // Navigate
    }
}

// List row
ListRow(
    title: "Workout Session",
    subtitle: "45 minutes",
    leading: AnyView(Image(systemName: "figure.run")),
    trailing: AnyView(Text("2h ago"))
)
```

### State Views

```swift
// Loading
LoadingView(message: "Loading data...")

// Empty state
EmptyStateView(
    icon: "photo",
    title: "No Photos",
    description: "Take your first photo",
    actionTitle: "Take Photo"
) {
    // Action
}

// Error
ErrorView(error: error) {
    // Retry action
}

// Success
SuccessView(
    title: "Success!",
    description: "Changes saved"
)
```

## View Modifiers

### Interactive Effects

```swift
// Scale on press
Button("Tap me") { }
    .interactiveScale()

// Shake animation
TextField("", text: $text)
    .shake(trigger: showError)

// Glow effect
Image(systemName: "star.fill")
    .glow(color: .yellow, radius: 10)
```

### Loading & Errors

```swift
// Loading overlay
ContentView()
    .loadingOverlay(isLoading: isLoading, message: "Saving...")

// Error banner
ContentView()
    .errorBanner($errorMessage)
```

### Layout Helpers

```swift
// Conditional modifier
Text("Hello")
    .conditional(
        isLarge,
        trueModifier: MyLargeModifier(),
        falseModifier: MySmallModifier()
    )

// Custom corner radius
Rectangle()
    .cornerRadius(20, corners: [.topLeft, .topRight])
```

## Best Practices

1. **Always use semantic colors** from the theme instead of hardcoded values
2. **Use appropriate spacing tokens** for consistent layouts
3. **Apply the theme environment** at the root of your app
4. **Prefer composition** over creating new components when possible
5. **Test components in both light and dark modes** (though app is dark-only)
6. **Use appropriate component sizes** based on context
7. **Maintain consistent animation timings** using theme animations

## Examples

### Complete Form View

```swift
struct ProfileForm: View {
    @Environment(\.theme) var theme
    @State private var name = ""
    @State private var email = ""
    @State private var bio = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                StandardTextField(
                    text: $name,
                    placeholder: "Enter name",
                    label: "Name",
                    icon: "person"
                )
                
                StandardTextField(
                    text: $email,
                    placeholder: "Enter email",
                    label: "Email",
                    icon: "envelope",
                    keyboardType: .emailAddress
                )
                
                TextArea(
                    text: $bio,
                    placeholder: "About you",
                    label: "Bio"
                )
                
                StandardButton("Save", style: .primary, fullWidth: true) {
                    // Save action
                }
            }
            .padding(theme.spacing.screenPadding)
        }
        .background(theme.colors.background)
    }
}
```

### Settings Screen

```swift
struct SettingsView: View {
    @Environment(\.theme) var theme
    @State private var notifications = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSection(title: "Account") {
                    SettingsRow(
                        icon: "person",
                        title: "Profile",
                        type: .navigation
                    ) {
                        // Navigate
                    }
                }
                
                SettingsSection(title: "Preferences") {
                    SettingsRow(
                        icon: "bell",
                        title: "Notifications",
                        type: .toggle(isOn: $notifications)
                    )
                }
            }
        }
        .background(theme.colors.background)
    }
}
```

## Migration Guide

To update existing views to use the design system:

1. Replace hardcoded colors with theme colors
2. Replace custom buttons with StandardButton
3. Replace custom cards with StandardCard
4. Replace text fields with StandardTextField
5. Update spacing values to use theme spacing
6. Apply consistent corner radius using theme values

## Contributing

When adding new components:

1. Follow the existing naming conventions
2. Support all relevant theme properties
3. Include comprehensive previews
4. Document usage examples
5. Consider accessibility
6. Test with dynamic type sizes