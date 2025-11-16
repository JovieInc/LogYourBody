# Phase 4  Action Hierarchy & Modal Audit

_Last updated: November 16, 2025_

This document summarizes the Phase 4 requirements:

1. **Primary action inventory**  every high-traffic screen must have exactly one primary CTA with no attention competition.
2. **Modal presentation standardization**  quick actions use `.sheet`, immersive flows use `.fullScreenCover`, and dismissal behavior is consistent.

## 1. Primary CTA Inventory

| Screen / Flow | Primary CTA | Supporting / Secondary Actions | Notes |
| --- | --- | --- | --- |
| `LoginView` | "Log in" button inside `LoginForm` | "Forgot password" link (placeholder) + "Sign up" link | Only one high-emphasis CTA; secondary links use text-only styling. |
| `SignUpView` | "Create Account" button inside `SignUpForm` | "Sign in" text link + alternative Apple sign-in button | Apple sign-in styled per design system but grouped as alternative auth; primary emphasis remains on e-mail sign up. |
| Onboarding  Welcome  Profile Prep (all steps) | Contextual `LiquidGlassCTAButton` ("Get Started", "Continue", "Go to Dashboard`) | Optional `LiquidGlassSecondaryCTAButton` variants (e.g., "Skip for Now") | Each step animates a single primary CTA. Secondary buttons only appear when skipping is acceptable and use low-emphasis styling. |
| `DashboardViewLiquid` | Floating glass FAB ("+ Add Entry") | Metric cards act as navigational buttons | FAB is the only persistent high-emphasis CTA; cards use plain buttons with subdued styling. |
| `DashboardViewV2` | Carousel floating FAB ("+") that launches camera/photo logging | Card taps drill into data, treated as secondary | Audit confirmed no duplicate FABs; hero header buttons remain informational. |
| `AddEntrySheet` | Footer button (`saveButtonText`) | Tab picker buttons | Only one actionable CTA rendered at a time ("Save Weight", "Save Body Fat", etc.). |
| `PreferencesView` | Toolbar "Save" button | Field-level pickers & toggles | Save button only appears when there are pending edits, ensuring clear hierarchy. |
| `ProfileSettingsViewV2` | Toolbar "Save" button | Navigation links to Security / Delete Account | Save button gated by `hasChanges`; destructive actions live in separate cards with secondary emphasis. |
| `LegalConsentView` | "Continue" blocker button | Checkbox toggles for ToS/Privacy | This view now presents as a full-screen cover to reinforce its single primary CTA. |
| `ExportDataView` | "Export Data" CTA inside confirmation dialog | Share Sheet triggered afterwards | Export button is the only high-contrast action on screen. |
| `IntegrationsView` | "Connect HealthKit" CTA within card | Informational rows | HealthKit connect remains sole emphasized action until authorization completes. |

**Result:** No audited screen presents more than one simultaneous high-emphasis CTA. Any secondary or alternative paths use lower visual weight (text links, secondary button styles, or contextual list rows).

## 2. Modal Presentation Audit

| Flow | Action Type | Presentation (Before  After) | Notes |
| --- | --- | --- | --- |
| `LegalConsentView` gating (triggered from `ContentView`) | Full-screen flow (blocking) | `.sheet`  `.fullScreenCover` with `interactiveDismissDisabled(true)` | Ensures users cannot peek underlying UI, matching the compliance requirement. |
| `DashboardViewV2` camera capture | Full-screen camera workflow | `.sheet`  `.fullScreenCover` | Aligns with camera behavior elsewhere (`DashboardView`, `DashboardViewLiquid`). |
| `DashboardView(Liquid)` quick photo source picker | Quick action | `.sheet` (unchanged) | Uses `.sheet` for lightweight photo/source selection. |
| `AddEntrySheet`, `Preferences` pickers, `ProfileSettings` pickers, `Integrations` authorization helper | Quick actions | `.sheet` (unchanged) | All remain sheets with contextual detents when applicable. |

**Guideline recap:**

1. Quick, dismissible utilities (pickers, lightweight forms, share sheets) must continue to use `.sheet`.
2. Immersive or blocking flows (camera, legal consent, onboarding full-screen steps) must use `.fullScreenCover` and control dismissal explicitly.
3. When presenting alternative actions from a primary screen, only one element may carry the "primary" visual treatment at any given time.

## 3. Follow-ups

1. Add UI snapshot tests for onboarding CTAs to guard against multiple `LiquidGlassCTAButton` instances per step.
2. Consider extracting a reusable `ModalStyle` helper to codify the `.sheet` vs `.fullScreenCover` rules.

This document should be updated whenever new screens or modal flows are introduced.
