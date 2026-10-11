---
title: Design staging handoff, app walk 2026-09-28
status: for the design pass in the Pen file; promote to canonical only after Tim approves
---

# What changed and what a design agent should cook on

Source of truth for each screen is the merged SwiftUI. Screenshots of the pre-refactor app (59 frames, walked on the LYB-Cert iPhone 17 Pro simulator) live outside the repo at `~/.codex/goals/lyb-app-walk/receipts/walk/` and show the before state. The Pen file is `~/Documents/LogYourBody iOS.pen`; new work goes into a root frame named `STAGING · App walk 2026-09-28 · Tim cooks here · promote when approved` and never into canonical frames.

Positioning frame for every screen, from [docs/product/icp.md](../product/icp.md): the customer spends money to look better naked. Copy speaks to appearance (fat off, muscle on, photos that prove it), never to general fitness or clinical health.

## 1. Settings, one native hierarchy (merged, #1158)

One `Form` hierarchy replaces the two overlapping settings roots. Native `NavigationStack`, toolbar back, `Picker`, `Toggle`, native editor sheets, Liquid Glass behind the existing availability gates. No custom card chrome, no bespoke back buttons.

- Profile: personal details and profile photo (name, date of birth, height; native wheel pickers and PhotosUI).
- Tracking: units, target (weight and body-fat targets, user-owned), daily step goal, activity, reminders.
- Account & subscription: subscription (manage, restore), Face ID lock, sign out.
- Privacy & data: photo handling, export data, delete account (typed confirmation).
- Integrations: Apple Health, scan import (see section 5).

Design questions: section order for an aesthetics-first customer (Profile and Target first?), whether Integrations merges into Tracking, and how much of the Liquid Glass treatment to keep on grouped rows versus plain inset lists.

## 2. Paywall, one canonical surface (merged, #1161)

One `PaywallView` for onboarding and settings. Monthly and annual plans with the three-day trial, one restore action, sign-out escape. Prices come from the product registry, never hard-coded in the design.

Design questions: the single line of value copy above the plans (appearance-first), whether the annual saving is shown as a badge or a sentence, and the placement of restore and sign out so they are findable but quiet.

## 3. Sign in and Today, one entry path (open, #1164)

One Sign in with Apple action shared by the signed-out wall and authenticated onboarding; the misnamed verify-account step is gone. One Today surface with the chat composer; the P0 entry actions (log weight, log body fat, add photo) route through one shared Add Entry sheet with the date and last values pre-filled.

Design questions: the signed-out wall's single line under the Apple button ("Apple is the fastest way back to your private history." today), and the hierarchy of the Today header versus the composer.

## 4. Today headline answers fat versus muscle (open, #1167)

The home headline shows body fat beside weight when a recorded body-fat reading exists, labeled by source (DEXA body fat, InBody body fat, estimated body fat). Interpolated estimates stay out of the headline. With no reading yet, the headline is a short prompt to track body fat beside weight. The GLP-1 dose log stays as a tracking-only reminder entry in Add Entry, never advice.

Design questions: the headline treatment for the two numbers and the trend glyph, and the empty-state prompt copy in appearance language.

## 5. DEXA and InBody PDF import on iOS (open, #1166)

Replaces the "BodySpec unavailable" screen. A file-picker and open-in entry lets the user import a scan PDF; the app posts it to the existing web parser, lands a dated scan result on the timeline, and keeps a scan history list. Sheet title today: "Import scan PDF", primary action "Add to timeline", section "Scan history".

Design questions: where the import entry lives for a scan-owning customer (Timeline add menu, Integrations, or both), the scan-result card on the timeline, and how a scan compares to the previous one at a glance (fat versus lean delta).

## 6. Talk entry (merged, #1151, gated off)

A single Talk control for voice logging exists behind `LYB_VOICE_ENABLED` and a Statsig gate. Spoken replies are one short imperative line. Design the resting and listening states of the control and the confirmation moment for a proposed set log; do not add a second entry point.

## Not in scope for this pass

GLP-1 recommendations of any kind; Apple Watch; iPad layouts; web app surfaces.
