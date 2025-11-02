# @logyourbody/design-tokens

Shared design tokens package for iOS (SwiftUI) and Web (Tailwind CSS) platforms. Provides a single source of truth for colors, spacing, typography, motion, and visual effects across the entire LogYourBody ecosystem.

## Architecture

```
packages/design-tokens/
├── tokens/                    # Source design tokens (JSON)
│   ├── core/                 # Platform-agnostic primitives
│   │   ├── colors.json       # Color palette
│   │   ├── spacing.json      # Spacing scale
│   │   ├── radii.json        # Border radii
│   │   ├── shadows.json      # Shadow definitions
│   │   ├── typography.json   # Font sizes, weights, line heights
│   │   └── motion.json       # Animation durations, easing, springs
│   ├── semantic/             # Meaningful abstractions
│   │   ├── actions.json      # Action colors (primary, destructive)
│   │   └── effects.json      # Glassmorphism effects
│   └── platform/             # Platform-specific overrides
│       ├── ios.json          # iOS-specific tokens
│       └── web.json          # Web-specific tokens
├── config/                   # Style Dictionary configurations
│   ├── style-dictionary.ios.js
│   └── style-dictionary.web.js
├── scripts/                  # Build automation
│   ├── build-ios.js
│   ├── build-web.js
│   └── validate-tokens.js
└── build/                    # Generated output (gitignored)
    ├── ios/                  # Swift code + xcassets
    └── web/                  # CSS, JS, TS, JSON, SCSS
```

## Token Structure

### Naming Convention

Tokens follow a hierarchical naming pattern:

```
{category}.{subcategory}.{variant}.{state}
```

Examples:
- `color.base.purple.500` - Core color primitive
- `color.semantic.primary` - Semantic color reference
- `spacing.semantic.element` - Semantic spacing value
- `color.action.primary.hover` - Stateful color

### Token Layers

1. **Core Tokens** - Raw values, platform-agnostic
   - Colors: Gray scale, brand colors, semantic colors
   - Spacing: xxxs (2px) to xxxl (64px)
   - Radii: xs (4px) to full (9999px)
   - Typography: Display, headline, body, label, caption sizes
   - Motion: Durations (100ms-500ms), easing curves, spring parameters

2. **Semantic Tokens** - References to core tokens with meaningful names
   - UI colors: background, foreground, border
   - Actions: primary, destructive (with hover states)
   - Status: success, warning, error, info
   - Effects: glassmorphism blur, opacity, borders

3. **Platform Tokens** - Platform-specific overrides (if needed)

### Token References

Tokens can reference other tokens using `{}` syntax:

```json
{
  "color": {
    "base": {
      "purple": {
        "500": { "value": "#5B63D3" }
      }
    },
    "semantic": {
      "primary": { "value": "{color.base.purple.500}" }
    }
  }
}
```

This creates a dependency chain - updating `purple.500` automatically updates `semantic.primary`.

## Building Tokens

### Install Dependencies

```bash
cd packages/design-tokens
npm install
```

### Build All Platforms

```bash
npm run build
```

This generates:
- **iOS**: `build/ios/DesignTokens.swift`, `build/ios/Colors.xcassets/`
- **Web**: `build/web/tokens.css`, `tokens.js`, `tokens.d.ts`, `tokens.json`, `tokens.scss`

### Build Single Platform

```bash
npm run build:ios    # iOS only
npm run build:web    # Web only
```

### Watch Mode

Auto-rebuild on token changes:

```bash
npm run watch
```

### Validate Tokens

Check for issues (missing values, contrast violations):

```bash
npm run validate
```

## Integration Guide

### iOS (SwiftUI)

#### 1. Add Generated Swift File to Xcode

After building, drag `build/ios/DesignTokens.swift` into your Xcode project:

1. Right-click your project in Xcode
2. Select "Add Files to LogYourBody..."
3. Navigate to `packages/design-tokens/build/ios/DesignTokens.swift`
4. Check "Copy items if needed"
5. Click "Add"

#### 2. Use Tokens in SwiftUI

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack(spacing: DesignTokens.spacing.semantic.element) {
            Text("Hello World")
                .font(DesignTokens.typography.headline.lg)
                .foregroundColor(DesignTokens.color.semantic.textPrimary)

            Button("Primary Action") {
                // action
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(DesignTokens.spacing.semantic.screen)
        .background(DesignTokens.color.semantic.background)
        .cornerRadius(DesignTokens.radius.semantic.card)
    }
}

// Glassmorphism Example
struct GlassCard: View {
    var body: some View {
        ZStack {
            // Glass background
            DesignTokens.color.semantic.card
                .opacity(DesignTokens.glass.opacity)

            // Content
            VStack {
                Text("Glass Card")
                    .foregroundColor(DesignTokens.color.semantic.textPrimary)
            }
            .padding(DesignTokens.spacing.semantic.card)
        }
        .background(.ultraThinMaterial) // iOS glassmorphism
        .cornerRadius(DesignTokens.radius.semantic.card)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radius.semantic.card)
                .stroke(Color.white.opacity(DesignTokens.glass.borderOpacity),
                       lineWidth: DesignTokens.glass.borderWidth)
        )
    }
}
```

#### 3. Animation with Motion Tokens

```swift
Button("Animate") {
    withAnimation(
        .spring(
            response: DesignTokens.motion.spring.interactive.response,
            dampingFraction: DesignTokens.motion.spring.interactive.damping
        )
    ) {
        isExpanded.toggle()
    }
}
```

### Web (Tailwind CSS + Next.js)

#### 1. Import CSS Variables

In your root layout or global CSS file:

```css
/* app/globals.css or styles/globals.css */
@import '@logyourbody/design-tokens/build/web/tokens.css';
```

Or in Next.js `_app.tsx`:

```typescript
import '@logyourbody/design-tokens/build/web/tokens.css';
```

#### 2. Configure Tailwind CSS v4

Update `tailwind.config.js` to use design tokens:

```javascript
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: 'var(--color-semantic-primary)',
        'primary-hover': 'var(--color-semantic-primary-hover)',
        background: 'var(--color-ui-background-primary)',
        card: 'var(--color-ui-background-secondary)',
        foreground: 'var(--color-ui-foreground-primary)',
        'text-secondary': 'var(--color-ui-foreground-secondary)',
        error: 'var(--color-semantic-error)',
        success: 'var(--color-semantic-success)',
      },
      spacing: {
        'element': 'calc(var(--spacing-semantic-element) * 1px)',
        'section': 'calc(var(--spacing-semantic-section) * 1px)',
        'screen': 'calc(var(--spacing-semantic-screen) * 1px)',
      },
      borderRadius: {
        'card': 'calc(var(--radius-semantic-card) * 1px)',
        'button': 'calc(var(--radius-semantic-button) * 1px)',
      },
      backdropBlur: {
        'glass': 'calc(var(--backdrop-blur-md) * 1px)',
      },
      fontFamily: {
        sans: 'var(--font-family-system)',
        mono: 'var(--font-family-mono)',
      },
    },
  },
  plugins: [],
};
```

#### 3. Use Tokens in React Components

```typescript
import tokens from '@logyourbody/design-tokens/build/web/tokens';

export function Card({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="bg-card rounded-card p-[var(--spacing-semantic-card)]"
      style={{
        borderRadius: `${tokens.radius.semantic.card}px`,
        padding: `${tokens.spacing.semantic.card}px`,
      }}
    >
      {children}
    </div>
  );
}
```

#### 4. Glassmorphism with Tailwind

```typescript
export function GlassCard({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative overflow-hidden rounded-card">
      {/* Glass background */}
      <div className="absolute inset-0 bg-card/80 backdrop-blur-glass" />

      {/* Glass border */}
      <div
        className="absolute inset-0 rounded-card border"
        style={{
          borderColor: `rgba(255, 255, 255, var(--glass-border-opacity))`,
          borderWidth: `${tokens.glass.borderWidth}px`,
        }}
      />

      {/* Content */}
      <div className="relative z-10 p-[var(--spacing-semantic-card)]">
        {children}
      </div>
    </div>
  );
}
```

#### 5. Motion with Framer Motion

```typescript
import { motion } from 'framer-motion';
import tokens from '@logyourbody/design-tokens/build/web/tokens';

export function AnimatedButton({ children }: { children: React.ReactNode }) {
  return (
    <motion.button
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      transition={{
        type: 'spring',
        stiffness: 1 / tokens.motion.spring.interactive.response,
        damping: tokens.motion.spring.interactive.damping,
      }}
      className="px-6 py-3 bg-primary hover:bg-primary-hover rounded-button"
    >
      {children}
    </motion.button>
  );
}
```

## Adding New Tokens

### 1. Edit JSON Files

Add tokens to appropriate files in `tokens/`:

```json
// tokens/core/colors.json
{
  "color": {
    "base": {
      "blue": {
        "500": {
          "value": "#3B82F6",
          "comment": "Bright blue accent"
        }
      }
    }
  }
}
```

### 2. Create Semantic References

```json
// tokens/semantic/actions.json
{
  "color": {
    "action": {
      "secondary": {
        "default": {
          "value": "{color.base.blue.500}",
          "comment": "Secondary action color"
        }
      }
    }
  }
}
```

### 3. Rebuild

```bash
npm run build
```

### 4. Update Xcode Project (iOS only)

If `DesignTokens.swift` changed, you may need to re-add it to Xcode or simply rebuild your iOS project.

## Migration Guide

### From Hardcoded Colors (iOS)

**Before:**
```swift
.foregroundColor(Color(red: 0.357, green: 0.388, blue: 0.827))
.padding(.leading, 16)
```

**After:**
```swift
.foregroundColor(DesignTokens.color.semantic.primary)
.padding(.leading, DesignTokens.spacing.md)
```

### From CSS Custom Properties (Web)

**Before:**
```css
.card {
  background: #1A1A1A;
  border-radius: 12px;
  padding: 16px;
}
```

**After:**
```css
.card {
  background: var(--color-ui-background-secondary);
  border-radius: calc(var(--radius-semantic-card) * 1px);
  padding: calc(var(--spacing-semantic-card) * 1px);
}
```

Or with Tailwind:
```tsx
<div className="bg-card rounded-card p-[var(--spacing-semantic-card)]" />
```

## Accessibility

### WCAG Contrast Compliance

All semantic text colors maintain WCAG AA contrast ratios:
- `color.semantic.text.primary` on `color.semantic.background`: 12.7:1 (AAA)
- `color.semantic.text.secondary` on `color.semantic.background`: 5.2:1 (AA)
- `color.semantic.text.tertiary` on `color.semantic.background`: 4.5:1 (AA minimum)

### Dynamic Type (iOS)

Use semantic typography tokens which automatically scale:

```swift
Text("Headline")
    .font(DesignTokens.typography.headline.md) // Scales with user preferences
```

### Reduced Motion (Web)

Check for `prefers-reduced-motion` and disable animations:

```typescript
import { motion } from 'framer-motion';

const shouldReduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

<motion.div
  animate={{ opacity: 1 }}
  transition={{
    duration: shouldReduceMotion ? 0 : tokens.motion.duration.medium / 1000,
  }}
>
  Content
</motion.div>
```

## Validation

Run validation to check for common issues:

```bash
npm run validate
```

Checks for:
- Missing token values
- Invalid color formats
- WCAG contrast violations
- Circular references
- Platform-specific token mismatches

## Best Practices

1. **Always use semantic tokens** in application code, not core tokens
   - Good: `DesignTokens.color.semantic.primary`
   - Bad: `DesignTokens.color.base.purple.500`

2. **Reference tokens, don't duplicate values**
   - Good: `{ "value": "{color.base.purple.500}" }`
   - Bad: `{ "value": "#5B63D3" }`

3. **Add comments to new tokens**
   ```json
   {
     "value": "#5B63D3",
     "comment": "Primary brand purple - used for CTAs and key actions"
   }
   ```

4. **Test on both platforms** after token changes
   - Run `npm run build`
   - Test iOS build in Xcode
   - Test web build with `npm run dev`

5. **Validate before committing**
   ```bash
   npm run validate
   ```

## Troubleshooting

### iOS Build Issues

**Problem:** `DesignTokens` not found in scope
- **Solution:** Ensure `DesignTokens.swift` is added to Xcode project and target membership is checked

**Problem:** Colors appear incorrect
- **Solution:** Verify color format is hex (e.g., `#5B63D3`) in JSON tokens

### Web Build Issues

**Problem:** CSS variables not loading
- **Solution:** Ensure `tokens.css` is imported in root layout/global CSS

**Problem:** Tailwind not recognizing custom values
- **Solution:** Update `tailwind.config.js` to extend theme with CSS variable references

### Build Errors

**Problem:** `Unknown transform` errors
- **Solution:** Ensure `style-dictionary.config.js` uses `transformGroup` instead of explicit `transforms` array

**Problem:** ES Module errors
- **Solution:** Verify `package.json` has `"type": "module"` and build scripts use `import` not `require()`

## Contributing

When adding new tokens:
1. Add to appropriate JSON file in `tokens/`
2. Create semantic references if needed
3. Update this README with usage examples
4. Run `npm run validate` to check for issues
5. Test on both iOS and web platforms
6. Commit both source tokens and generated files

## License

UNLICENSED - Private use only
