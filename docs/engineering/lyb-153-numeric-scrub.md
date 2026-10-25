# LYB-153 workout numeric scrub

The existing live training row and correction sheet use `TrainingNumericScrub`
when the `workout_numeric_scrub_v1` Statsig gate is enabled through the platform
analytics port. The initializer defaults to disabled; an absent gate leaves the
existing TextFields and RIR Stepper in place.

The primitive edits reported performance, never training prescriptions. It uses
the existing reps/load/RIR bindings into `TrainingSessionDraft`. Horizontal drag
changes gesture-local state; release writes the binding once. Logging and
correction still require their existing explicit actions and durable identities.
Pending submissions disable the controls. There is no new data store or network
path.

- Reps: 1–50, integer steps. RIR: 0–6, integer steps.
- Load: 0–500 canonical kg, displayed in the user's chosen kg/lbs unit.
  Conversion occurs at the input boundary. Unchanged pound displays never
  round-trip the stored kilogram value.
- Default input increments: 0.5 kg or 1 lb. The load menu offers 0.25, 0.5, 1,
  1.25, 2.5, 5 and 10 in the displayed unit, so users can select the increment
  available on their equipment. The training contract has no equipment increment
  or per-hand field; this control preserves its existing load convention and
  never multiplies a per-hand value. Tap entry accepts other decimal loads.
- Normal movement: 12 points per step. Moving 44 points up switches to 48 points
  per step without changing the current value. Moving 80 points down cancels the
  gesture. Haptics occur only when a snapped value changes; no flick momentum.
- Vertical scrolling wins directional recognition. UIKit gesture cancellation,
  scene interruption, disabling the control, changing units/rows or a changed
  binding discards provisional work. Numeric entry has explicit Done/Cancel.
- VoiceOver exposes adjustable and numeric-entry actions. Visible +/- targets
  are at least 44 points. Accessibility type stacks the live fields vertically.
  Drag updates have no animation, including with Reduce Motion enabled.

Rest is a bounded seconds configuration (0–3600, 5-second input steps) in unit
tests and the native preview only. **No live rest-timer adoption is included.**
LYB-116 owns the real editable rest-time contract; its owner must supply that
binding and authoritative bounds before adopting the primitive.

## Validation and remaining native acceptance

On the Linux implementation host:

- `corepack pnpm lint`, `corepack pnpm typecheck`, `corepack pnpm test`: passed.
  The test suite needed execution outside the sandbox after subprocess/socket
  operations failed with EPERM inside it. No checks were disabled.
- Strict SwiftLint on all six changed Swift files: zero violations. This Linux
  binary reports that five SourceKit-dependent rules cannot run on this host.
- Swift 6.2.1 syntax parsing: passed for all six changed Swift files.
- Nine `TrainingNumericScrubTests` passed in an isolated Linux SwiftPM harness
  using the production policy, unit-conversion source and canonical load parser.
  Only the preference-key constant was stubbed. This does not execute SwiftUI,
  UIKit, Core Data or the native app runner.
- Regression proof: `testFastAndSlowSamplesReachTheSameValueWithoutFlickOvershoot`
  failed with slow sampling producing 15 rather than 16 before step accumulation
  was normalized, then passed after the fix.

The Xcode project includes the new unit and UI suites in their real targets.
Two draft integration tests cover pre-release journal isolation, offline replay,
canonical relaunch readback, correction identity and duplicate-submit prevention.
Five XCUITests cover the three live dimensions, fast/slow drag, cancellation,
keyboard entry, pounds-to-kg readback, background interruption, offline retry,
large type, Reduce Motion and reachable safe-area controls. Native previews show
all four primitive dimensions, including an accessibility-size fixture.

**These native integration/UI suites have not run on this Linux host.** Before
rollout, run the repository's `bundle exec fastlane ios ci_test_unit` lane and
the UI suite through `bundle exec fastlane ios test_ui` on its supported
macOS runner, preserving current coverage gates and exact-commit receipts.
VoiceOver behavior, interruption during an active touch, rest adoption, 200%
Dynamic Type and hitch-free operation on a supported real iPhone remain native
acceptance work; portable tests and syntax parsing do not establish those facts.

The harness owns commit pushing, PR creation and merge. No push, PR operation,
Statsig rollout or release was performed during implementation.
