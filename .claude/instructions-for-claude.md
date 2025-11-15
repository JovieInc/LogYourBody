# Instructions for Claude - LogYourBody Project

## Critical Design System Rules

### 1. Component Integration Rule
**Never create new UI components without immediately integrating them into active views.**

When creating a new component:
- [ ] Create the component file
- [ ] **IMMEDIATELY** update the relevant view to use it
- [ ] **VERIFY** the component is visible in the actual app (not just created in DesignSystem folder)
- [ ] Remove or deprecate the old component being replaced
- [ ] Test the integration before marking work complete

**Why**: We discovered that beautifully designed components (MetricSummaryCard, AllMetricsRow) were created but never integrated, leaving users with outdated UI while perfect designs sat unused.

### 2. Deprecation & Migration Rule
**When replacing components, explicitly mark old ones as deprecated and create a clear migration path.**

For every component replacement:
- [ ] Add `@available(*, deprecated, message: "Use NewComponent instead")` to old component
- [ ] Add detailed deprecation comments explaining why and how to migrate
- [ ] Update all existing usages to the new component
- [ ] Document the migration in comments or PR description
- [ ] Verify no active code is using the deprecated component

**Example**:
```swift
/// **DEPRECATED**: Use `MetricSummaryCard` from `DesignSystem/Organisms/MetricSummaryCard.swift` instead.
///
/// Migration guide:
/// - Replace `DSMetricCard` with `MetricSummaryCard`
/// - Use the `.data(Content(...))` state with proper data binding
@available(*, deprecated, message: "Use MetricSummaryCard instead")
struct DSMetricCard: View { ... }
```

### 3. Design System Audit Rule
**Before completing any UI work, verify the new design is actually visible in the app.**

Completion checklist for UI tasks:
- [ ] Component created and polished
- [ ] Component integrated into active view (not just DesignSystem folder)
- [ ] Old component deprecated or removed
- [ ] Changes visible in running app (build & test)
- [ ] Screenshot or demo shows the new design in action
- [ ] No duplicate/parallel implementations exist

**Why**: Design drift occurs when new components live in parallel with old ones, confusing developers and fragmenting the design system.

### 4. Single Source of Truth
**Maintain ONE active version of each component type; delete or clearly deprecate alternatives.**

Before creating a new component:
- [ ] Search for existing similar components (Glob/Grep for similar names)
- [ ] If found, decide: improve existing OR create new + deprecate old
- [ ] Never create `ComponentV2`, `ComponentNew`, etc. - replace the original
- [ ] Avoid local/private components that duplicate DesignSystem components

**Anti-pattern detected**:
- ✗ DashboardViewLiquid.swift had a `private struct MetricSummaryCard`
- ✗ DesignSystem/Organisms/MetricSummaryCard.swift existed with better design
- ✗ Local version shadowed the global one, hiding improvements

**Correct pattern**:
- ✓ Single `MetricSummaryCard` in DesignSystem/Organisms/
- ✓ All views import and use the same component
- ✓ Improvements benefit entire app immediately

### 5. Component Naming & Organization
**Follow atomic design hierarchy strictly.**

- **Atoms** (`DesignSystem/Atoms/`): Smallest building blocks (buttons, labels, icons)
- **Molecules** (`DesignSystem/Molecules/`): Simple combinations of atoms (card headers, input groups)
- **Organisms** (`DesignSystem/Organisms/`): Complex components (full cards, lists, forms)
- **Templates/Views** (`Views/`): Page-level layouts using organisms

**Prefixing convention**:
- DesignSystem components: `DS` prefix (e.g., `DSButton`, `DSMetricValue`)
- Organism-level: No prefix needed if clearly in Organisms folder (e.g., `MetricSummaryCard`)
- View-level: Descriptive name (e.g., `DashboardViewLiquid`, `SettingsView`)

### 6. Testing & Verification
**Always build and visually verify UI changes.**

For every UI component change:
- [ ] Run `xcodebuild` or equivalent build command
- [ ] Open iOS Simulator or deploy to device
- [ ] Navigate to the screen using the component
- [ ] Take a screenshot or describe what you see
- [ ] Verify spacing, colors, fonts match design spec
- [ ] Test in both light and dark modes if applicable

### 7. Documentation & Communication
**Document design decisions and component purposes clearly.**

Every component file should have:
- Clear description of purpose
- Usage examples in comments
- State what it replaces (if applicable)
- Accessibility considerations
- Any layout constraints or assumptions

**Example**:
```swift
//
// MetricSummaryCard.swift
// LogYourBody
//
// Apple Health-inspired metric summary card with full state support
// Replaces: DSMetricCard, DSCompactMetricCard (deprecated)
//
// Features:
// - Material backgrounds (glassmorphism)
// - Full state management (loading, empty, error, data)
// - Dynamic type & accessibility support
// - Responsive chart sizing
//
```

## Enforcement Checklist

When working on UI components, **always** run through this checklist:

1. **Before creating a new component**:
   - [ ] Search for existing similar components
   - [ ] Decide: improve existing OR create new with migration plan

2. **When creating a new component**:
   - [ ] Place in correct atomic design folder (Atoms/Molecules/Organisms)
   - [ ] Add clear documentation header
   - [ ] Follow design system constants (Theme.swift spacing, colors, typography)

3. **After creating a new component**:
   - [ ] **IMMEDIATELY** integrate into active view
   - [ ] Deprecate old component if replacing
   - [ ] Build and verify in simulator/device
   - [ ] Take screenshot showing new design

4. **Before marking task complete**:
   - [ ] New design is visible in app (not just created)
   - [ ] Old components deprecated or removed
   - [ ] No duplicate implementations
   - [ ] Committed and pushed changes

## Key Lessons from MetricSummaryCard Issue

**Problem**:
- `MetricSummaryCard` with Apple Health polish was created in DesignSystem/Organisms/
- `DashboardViewLiquid.swift` had local `private struct MetricSummaryCard` with basic styling
- Local version shadowed the polished one, users saw outdated design
- New design sat unused for days/weeks

**Solution**:
1. Removed local private MetricSummaryCard from DashboardViewLiquid
2. Updated all calls to use DesignSystem version with proper state API
3. Increased chart height from 52pt to 80pt for better visibility
4. Deprecated DSMetricCard and DSCompactMetricCard with clear migration notes
5. Created this document to prevent recurrence

**Prevention**:
- Never create local/private components that duplicate DesignSystem components
- Always search before creating ("Does this already exist?")
- Integrate immediately, don't create orphaned designs
- Verify changes are visible before completing task

---

## Design System Constants (Reference)

Always use these instead of hardcoded values:

**Spacing** (Theme.spacing):
- xs: 4pt
- sm: 8pt
- md: 12pt
- lg: 16pt
- xl: 20pt
- xxl: 24pt

**Border Radius** (Theme.radius):
- button: 12pt
- card: 12pt
- input: 8pt

**Typography**:
- Use `.rounded` design for modern Apple feel
- Value sizes: 44-48pt (large), 34pt (medium)
- Labels: 14pt medium weight
- Timestamps: 12-13pt with reduced opacity

**Colors** (Color+Theme.swift):
- Use `Color.appPrimary`, `Color.appCard`, etc.
- For glassmorphism: `.ultraThinMaterial` background + `Color.white.opacity(0.08)` border
- Accent colors: liquidAccent (#6EE7F0) for interactive elements

---

**Remember**: The design system only works if everyone uses it. Creating beautiful components means nothing if they're not integrated. Always verify your work is visible in the actual app.
