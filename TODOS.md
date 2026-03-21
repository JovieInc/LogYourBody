# TODOS

## 3D Mesh Avatar Privacy Mode

**What:** Alternative scrubber display that shows a generic 3D torso mesh morphed to approximate the user's body fat % at each timestamp, instead of actual progress photos.
**Why:** Some users want body composition tracking without photos on their phone (privacy, sharing concerns). This was identified as a long-term "whoa" factor during office hours.
**Pros:** Expands audience, unique differentiator, cool demo.
**Cons:** Requires SceneKit/RealityKit, 3D mesh assets, bf%→mesh mapping research. This is an "ocean" — significant effort beyond current codebase.
**Context:** The hero scrubber (Phase 2) must be stable first. This would be a second display mode toggled from the scrubber UI.
**Depends on:** Hero scrubber complete and stable.

## Predictive DEXA — Estimate Body Composition from Scale + Photos

**What:** ML model predicting DEXA-equivalent body fat %, lean mass, and regional composition from smart scale readings + progress photos.
**Why:** DEXA scans cost $50-60/quarter. Continuous DEXA-grade insights from daily scale data would be a killer feature justifying premium pricing.
**Pros:** Massive value prop, strong differentiator.
**Cons:** Requires ML/CV research, training dataset of paired (scale, DEXA) measurements across many users, accuracy validation. Multi-quarter project.
**Context:** Start with forward projections (trend extrapolation) as a simpler precursor. Need significant user base with both data types for training.
**Depends on:** Large user base with paired DEXA + scale data.

## Stripe Billing Integration

**What:** Connect existing subscription UI ($9.99/mo, $69.99/yr) to Stripe payment processing. Paywall views exist on both iOS and web but buttons are no-ops.
**Why:** Required before onboarding anyone beyond personal use. Design doc deferred to focus on stability + hero feature.
**Pros:** Revenue, validates willingness to pay, enables friend/early-user onboarding.
**Cons:** Stripe SDK, webhook handling, receipt validation, subscription state across iOS + web.
**Context:** Pricing UI at `/settings/subscription` (web) and `PaywallView.swift` (iOS). No Stripe SDK in deps yet.
**Depends on:** App stable and daily-driveable (Phases 1-3 complete).

## Create DESIGN.md (Design System Source of Truth)

**What:** Document the existing Liquid Glass design system (Theme.swift, Color+Theme.swift) as a human-readable DESIGN.md — philosophy, color palette, typography scale, spacing, component patterns, usage guidelines.
**Why:** The token system exists in code but the "why" behind choices is scattered. Every new contributor reinvents decisions. A single design doc prevents drift.
**Pros:** Single source of truth, faster onboarding, design consistency.
**Cons:** Needs maintenance when tokens change.
**Context:** Run `/design-consultation` to generate. The design exploration from the plan-design-review (2026-03-19) captured the full token inventory — use that as input.
**Depends on:** Nothing — standalone task.
