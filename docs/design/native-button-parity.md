# Native button parity contract

Status: [draft PR1228](https://github.com/JovieInc/LogYourBody/pull/1228); native acceptance pending. This is a source comparison, not a completed screen audit or launch certification.

## Evidence and scope

LYB source baseline: `d83b3466f1d45e582bafd9ee35e1e250368121a3`, matching the externally distributed 1.2.0 / 20261006222024 baseline supplied by the release owner. Worktree: `fix/ios-design-parity-controls`.

Jovie reference was verified against GitHub main `58e35b232dc4f0bf6e0987fec0c591cc99a075d8`. Earlier local Jovie worktrees were stale; they are not current authority. The relevant source families are `packages/ui/atoms/button.tsx`, `apps/ios/Jovie/DesignSystem/JovieTheme.swift`, `DESIGN.md`, and `canon/DESIGN.md`. Jovie retains button content with zero opacity under an overlaid loading spinner, disables the action, and exposes busy state.

Changed files: shared `DesignSystem/Atoms/BaseButton.swift`, its existing `BaseButtonPolicyTests.swift`, and this report. No onboarding, Settings, auth, HealthKit, sync, training persistence, Xcode target, scheme, Fastlane, or CI workflow edits. Native tests use the existing test target and will remain in its CI suite.

The only simulator image captured by this lane, `design-evidence/00-observed-simulator.png`, showed SpringBoard and was rejected as product evidence. Simulator inspection subsequently stalled and was cancelled. No app fixture was launched by this lane, no real health record was changed, and no accepted current-build before/after screen evidence exists yet.

### Historical training fixture diagnostic

Four existing attachments from the reliability owner's earlier `ui-final.xcresult` were inspected read-only. Their manifest records iPhone 17 Pro, synthetic `-lybUITestTrainingFixture` tests, and Oct 6 capture timestamps. Three images show fixture status counters and are not product-screen evidence. The fourth, `reliability-evidence/ui-final-attachments/653779DA-DD85-443A-A4C8-E09E808EEBB8.png`, shows the actual restored live-session sheet: RIR and recovery Stepper labels, stepper controls, and unselected performance segments appear nearly black on dark cards. Exercise names, saved status, and explicitly styled headings remain readable.

Current `TrainingViews.swift` explicitly styles those headings but leaves the Stepper and Picker families to inherited native appearance while supplying dark card backgrounds. This supports a concrete appearance diagnostic; the historical capture's exact source SHA was not established, so it does not prove a defect in the distributed baseline or validate this button change. Reproduce on current source under both inherited light and dark appearance, plus large Dynamic Type, before changing those controls. The proposed visual-only TrainingViews scope was reported to the parent for reconciliation with the reliability owner; no edits were made there.

## Source-confirmed gaps and parity contracts

| Area                    | Current source evidence                                                                                                                                                                                          | Contract / disposition                                                                                                                                                                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Loading controls        | LYB replaces `label()` with a bare spinner and applies a 0.96 loading scale. Intrinsic width and large-type height therefore lose the label's contribution. Jovie retains its children and overlays the spinner. | Keep the label in layout while loading; keep the control's accessible name, expose a busy value, and disable duplicate actions. Implemented behind `native_button_loading_parity_v1`; native render proof pending.                                           |
| Typography and geometry | LYB's native contract is SF system text, medium action labels, 32pt visible pills, and at least 44pt hit areas. Jovie's web text-control contract is 28px, while its native ActionButton metrics remain 32pt.    | Compare platform-specific contracts. Preserve native Dynamic Type growth and existing LYB geometry. Do not copy web density or change locked native tokens from an obsolete reference.                                                                       |
| Spacing                 | LYB shared screen inset 20pt, compact inset 16pt, tight gap 8pt, item gap 12pt, section gap 28pt. HomeV2 adds another token family.                                                                              | Keep shared semantic spacing; verify active families in real screens before consolidating. No token migration in this slice.                                                                                                                                 |
| Controls                | `StandardButton` and `LiquidGlassCTAButton` wrap `BaseButton`; HomeV2 has a separate 52pt primary control. The latter clamps its label to one line with scale-down.                                              | Distinguish authentication/dock controls from compact utility actions. Audit long labels and accessibility sizes before changing shared wrappers.                                                                                                            |
| Navigation              | Native Settings and onboarding routes have separate owners. Open drafts 1169, 1209, and 1211 overlap those routes; UI-runner drafts 1163, 1165, and 1140 own schemes/Fastlane/workflows.                         | Preserve platform back, dismissal, and focus behavior; reconcile those owners before editing routes or UI-runner wiring.                                                                                                                                     |
| Accessibility           | BaseButton currently removes its original label from the view tree during loading. Enabled state combines configuration, loading, and environment availability.                                                  | Preserve the native Button role, the original label and disabled semantics, and caller identifiers. The gate-on path uses an accessibility representation and hides its decorative spinner. VoiceOver and XCUI identifier propagation still need acceptance. |
| Motion                  | BaseButton respects Reduce Motion for scale and its implicit animations, but the press gesture still creates a separate explicit animation.                                                                      | Busy state should not look pressed. This slice removes the loading shrink on the gated path. Gesture motion needs separate native validation before broad change.                                                                                            |
| Error / empty states    | Shared ErrorStateView uses semantic text styles and a retry action; HomeV2 supplies system-state fixtures. Real loaded/empty/offline/error layouts have not been captured in this run.                           | Recovery must be reachable, values retained, errors readable, and empty states actionable. These are acceptance requirements, not screenshot-confirmed findings.                                                                                             |
| Workout usability       | TrainingViews has stable reps/load/RIR and log-set identifiers, saved/disabled states, and inline load errors. The reliability owner owns those service bindings and state transitions.                          | Audit keyboard reachability, exercise/set context, long text, saved/error states, and one-handed targets with synthetic sessions. Coordinate individual visual hunks before editing TrainingViews. No persistence changes in this lane.                      |
| Web                     | LYB's existing web Button is an older Radix/CVA control with rounded-md, fixed heights, and no shared loading API. Web is limited to marketing/legal/support/account until native usage thresholds are met.      | Funnel owner retains web surfaces. Document the semantic gap; do not introduce a new web product or bulk-copy Jovie layouts.                                                                                                                                 |

## First bounded correction

`native_button_loading_parity_v1` is a new runtime check through the existing analytics port. The live gate was not created or changed. Without enablement, the existing loading presentation remains intact. A DEBUG-only environment override exercises both branches in component tests without credentials, live provider calls, or health data.

The enabled branch retains the styled label under an overlaid spinner, preserves width and Dynamic Type height, exposes the original action through a native Button accessibility representation with a `Loading` value, and remains disabled while busy. Locked height, shape, color, navigation, data writes, and haptics are not migrated.

## Regression checks

`BaseButtonPolicyTests` adds rendered-size comparisons for idle/loading at `.large`, `.xxxLarge`, `.accessibility1`, `.accessibility3`, and `.accessibility5`; constrained widths 160/240/320pt; full-width and custom-height controls; and icon labels. It also verifies the exact gate key and the unchanged gate-off presentation. A capture test retains eight ImageRenderer attachments comparing gate-off/gate-on idle/loading at default and accessibility3 sizes.

These tests are written but were not executed in this session. SwiftLint with `--strict --no-cache` passed with zero violations; Swift frontend parsing and `git diff --check` passed. Neither proves Swift typechecking, render behavior, accessibility, or a successful build.

Hosted CI at head `efdc662a7a8eb2e3eca2dd70d6c0570033c591da` reached test compilation and caught an invalid attempt to set the read-only `accessibilityReduceMotion` environment value in the capture fixture. The local correction freezes capture animations with a writable transaction instead. Independent inspection of the installed SwiftUI interfaces confirms the API correction; compilation and test execution of the corrected fixture remain pending. Static capture animation control does not test the system Reduce Motion setting. Further publication is held by the parent.

Root lint, typecheck, and tests passed through the pinned pnpm 10.34.1 CLI, with all Turbo tasks satisfied from cache (4/4, 4/4, and 8/8 respectively). These checks cover the unchanged JavaScript workspace and do not execute the native tests. Evidence logs are in the lane workspace's `design-evidence` directory.

Two serial native build-for-testing attempts exited 74 before compiling this change. Moving the Clang module cache and package cache into the lane workspace removed the module-cache permission error; SwiftPM still attempted to write manifest diagnostics under `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading`, which the sandbox denied. Signing, hooks, and thresholds were not bypassed.

The second failing command, run from this worktree, was:

```sh
CLANG_MODULE_CACHE_PATH=/Users/timwhite/Documents/Codex/2026-10-06/task-2/lyb-design-derived/ModuleCache.noindex \
SWIFTPM_MODULECACHE_OVERRIDE=/Users/timwhite/Documents/Codex/2026-10-06/task-2/lyb-design-derived/ModuleCache.noindex \
xcodebuild build-for-testing \
  -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Users/timwhite/Documents/Codex/2026-10-06/task-2/lyb-design-derived \
  -packageCachePath /Users/timwhite/Documents/Codex/2026-10-06/task-2/lyb-design-derived/SwiftPMCache \
  -disableAutomaticPackageResolution \
  -only-testing:LogYourBodyTests/BaseButtonPolicyTests
```

Exact denied diagnostic path: `/Users/timwhite/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/statsig-kit.dia` (also `sentry-cocoa.dia` and `purchases-ios.dia` in that directory). See `design-evidence/native-build-workspace-cache.log`. Further native builds and UI runs are paused: the parent revoked this lane's reservation while reliability owns the active regression run. Resume only through a newly coordinated slot and the supported approval flow; do not work around the sandbox denial.

Independent review found no proven compile or runtime defect in the two Swift file diffs. It identified one P2 coverage gap: the new accessibility representation still requires executable checks for the original name and caller identifier, one accessible button, the `Loading` value, and suppressed activation while loading or disabled by either configuration or parent environment. Source inspection confirms the existing `handleTap` guard, but does not prove the accessibility tree.

Signed native build/test, that review closeout, accepted screenshots, and draft PR publication are still required before this slice can be called validated. Local shell and escalation calls became unreliable after simulator inspection; one coordination tool's automatic permission review timed out. Unconfirmed operations must not be reported as success.

## Native acceptance sequence

1. Confirm the parent-assigned exclusive UI/build slot and a clean source identity. Prepare a secret-free development config using the repository bootstrap command.
2. Run the existing native test target serially with only `BaseButtonPolicyTests` selected, keeping signing and all existing quality thresholds. Export and inspect all eight component attachments.
3. Capture synthetic full-dashboard/day-zero, Add Entry, offline/error, and training live-session states. For each numbered step, record source/build identity, fixture arguments, Dynamic Type size, Reduce Motion, accepted screenshot, and observed behavior. Never erase a simulator or use a live health account.
4. Verify the idle/loading control's accessible name, caller identifier, busy value, disabled action, and unchanged frame in XCUI/VoiceOver. Confirm large text reflows without clipping and Reduce Motion removes movement.
5. Run root lint/typecheck/test through pinned pnpm, resolve independent review findings, and create a draft PR with passing and blocked checks separated. Do not enable the gate, merge, or release without parent coordination.

Rollback is leaving the gate off. Broader screen, type, spacing, navigation, motion, and workout changes remain evidence-dependent and owner-coordinated.
