# Real-Device Chaos Testing

A seeded, deterministic monkey test plus twelve targeted edge cases that hammer the running app on a real iPhone to find crashes, hangs, blank screens, and broken input handling that scripted golden-path tests don't reach.

## What runs

- `apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift` — `testChaosMonkey` drives a seeded random walk (tap 55%, swipe 15%, type an edge-case string 15%, dismiss/back 10%, background/foreground 5%) over the accessibility tree for a configurable number of steps. Every run is reproducible from its seed.
- `apps/ios/LogYourBodyUITests/ChaosEdgeCaseUITests.swift` — twelve named tests for behavior the monkey is unlikely to hit reliably on its own: numeric boundary values, rapid double-tap save, backgrounding mid-save, settings round trips, the paywall, the DEXA import sheet, and more.
- `scripts/ios/chaos-device.sh` — runs both suites against a connected device, exports every xcresult attachment, and writes `issues.json`.
- `scripts/ios/chaos-issues-from-xcresult.py` — the xcresult-to-`issues.json` summarizer `chaos-device.sh` calls.

## Running it

```bash
# Full run (250 steps), default seed, default fixture
scripts/ios/chaos-device.sh

# Short smoke run
LYB_CHAOS_STEPS=40 scripts/ios/chaos-device.sh

# Replay a specific seed/fixture combination that found a bug
LYB_CHAOS_SEED=20260928 LYB_CHAOS_STEPS=250 \
  LYB_CHAOS_FIXTURE=-lybUITestFullDashboardFixture \
  scripts/ios/chaos-device.sh
```

The shared project's signing settings carry stale manual overrides (a distribution provisioning profile and an `Apple Distribution` code signing identity) that conflict with automatic development signing on a real device. `chaos-device.sh` passes `CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY=Apple Development`, and blank `PROVISIONING_PROFILE`/`PROVISIONING_PROFILE_SPECIFIER` as command-line-only build setting overrides so this resolves without touching the committed project file.

Override the target device, team, or derived data location with `DESTINATION`, `DEVELOPMENT_TEAM`, or `DERIVED_DATA_PATH`. By default the script always does a build+test pass (`xcodebuild test`), which xcodebuild resyncs incrementally against `DERIVED_DATA_PATH` when a matching cache exists, so it stays fast on reruns from the same worktree without risking a stale binary. Pass `SKIP_BUILD=true` to force `test-without-building` when you already know the exact binary under `DERIVED_DATA_PATH` matches your current sources (for example, immediately after a prior run from the same worktree with no source changes since).

Each run writes to its own timestamped path, so reruns never clobber prior evidence:

- `~/.codex/goals/lyb-chaos/results/chaos-<timestamp>.xcresult`
- `~/.codex/goals/lyb-chaos/results/chaos-<timestamp>.attachments/` (screenshots + accessibility-tree dumps)
- `~/.codex/goals/lyb-chaos/results/chaos-<timestamp>.issues.json`

**Never commit an `.xcresult` bundle or its exported attachments.**

### Env vars the monkey reads

| Var | Default | Meaning |
| --- | --- | --- |
| `LYB_CHAOS_SEED` | `20260928` | Seeds the deterministic RNG; same seed + steps + fixture always drives the same sequence of actions. |
| `LYB_CHAOS_STEPS` | `250` | Number of monkey steps. |
| `LYB_CHAOS_FIXTURE` | `-lybUITestPhotoTimelineHUDFixture` | Launch argument that seeds initial app state. |

`chaos-device.sh` forwards these into the on-device test process via `TEST_RUNNER_*`-prefixed environment variables, which `xcodebuild` strips before injecting them into the XCUITest runner.

## Triage: reading `issues.json`

Each entry is one failed test:

```json
{
  "test": "ChaosMonkeyUITests/testChaosMonkey()",
  "result": "Failed",
  "messages": ["..."],
  "screenshots": ["/path/to/chaos-20260928-step-125-anomaly.png", "..."]
}
```

For `testChaosMonkey`, also open the `chaos-<seed>-summary` attachment: it lists every anomaly the monkey recorded (with the step number) even when the overall run still passed, plus how many system alerts the interruption monitor dismissed.

Classify each finding into one of these buckets before filing or fixing:

1. **Crash** — `app.state` left `.runningForeground` unexpectedly, or the process is gone in the screenshot/tree dump. Highest priority; check `~/.codex/goals/lyb-chaos/results/*.xcresult` diagnostics report for a crash log. A `Test crashed with signal kill` result for `testChaosMonkey` with a long run of identical per-step anomalies right before it usually means the monkey got wedged (see Known limitations), not a genuine app crash — confirm by checking whether the anomaly screenshots right before the kill all show the same screen.
2. **Hang** — an element query exceeded the 10s threshold. Note which screen/step; look for a synchronous call on the main thread near that surface.
3. **Dead tap** — the monkey tapped a hittable, non-denylisted control and nothing happened (compare the screenshot before/after the same step in the tree dump). Usually a missing gesture handler or a control that's visually enabled but functionally disabled.
4. **Layout clip** — an element's frame extends outside the window bounds, or text is visually cut off in a screenshot. See `testVeryLongProfileNameRendersWithoutClipping` for the pattern.
5. **Data loss** — a save that should have persisted didn't (check `testRapidDoubleTapSaveCreatesOneEntry` and `testBackgroundingDuringSaveThenForegroundingPreservesState` first; they target exactly this).
6. **Copy** — a validation or recovery message is missing, wrong, or not plain-language (see `LogWeightFormValidator`/`ValidationService` for the source of truth on weight/body-fat error copy).

File anomalies that recur across seeds or land in a golden-path surface as regular issues; a single non-reproducing anomaly at a random monkey step is lower priority than a targeted edge-case test failing, since the edge-case tests are deterministic and always exercise the same path.

## Known limitations

- **Face ID / passcode lock on the test device previously blocked most navigation-based tests, and is now bypassed.** If the device's `biometricLockEnabled` app preference is on (Settings → the "Face ID lock" toggle, identifier `home_v2_settings_face_id`), the app gates its whole `ContentView` behind a LocalAuthentication challenge on every relaunch, which XCTest cannot dismiss (`addUIInterruptionMonitor` explicitly cannot handle a `com.apple.localauthentication.ax.authentication.alert`; Apple's own log line says "If your test failed after this unhandled interruption, please file a bug"). `ContentView.disableBiometricLockForUITests` now checks for the `-lybUITestDisableBiometricLock` launch argument (same pattern as `-lybUITestSuppressWhatsNew`) and both chaos launch sites pass it, so this no longer blocks the harness. If you see `com.apple.localauthentication.ax.authentication.alert` in a chaos run's log again, check that both `ChaosMonkeyUITests` and `ChaosEdgeCaseUITests.launch()` still pass the flag.
- **A denylist-only escape screen can wedge the monkey.** The paywall denylists purchase, restore, and log out — if the monkey lands there, it has no legal move and previously sat recording an anomaly every step until the OS killed the runner (observed 2026-09-28: `Test crashed with signal kill` followed by the automation session failing to reinitialize, after ~90 consecutive per-step anomalies starting the moment it landed on `world_class_screen_paywall`). `ChaosMonkeyUITests`'s `StuckDetector` now recognizes this (no hittable non-denylisted elements, or an identical element fingerprint, for several consecutive polls) and relaunches with the seeding fixture, counting exactly one anomaly per episode instead of one per step. Landing on `world_class_screen_paywall` specifically triggers an immediate relaunch rather than waiting out the threshold, since there is no control on that screen the monkey is ever allowed to press.
- **Photo permission denial** (`testPhotoPermissionRecoveryCopyMatchesCurrentAuthorizationState`) can't force `PHPhotoLibrary` into a denied state — there's no UI-test fixture for it, and toggling the real device's photo permission is hard to reverse and would affect other concurrent test runs on the same shared device. The test asserts the surface renders (either the scanning UI or recovery copy) without crashing, whatever the device's current permission state happens to be, and documents this here instead of faking coverage. Reaching the bulk-import entry point at all also requires `-lybUITestBulkPhotoImportEnabledFixture`; without it, `BulkProgressPhotoImportPolicy` hides the row unless the fixture account already has two or more seeded progress photos.
- **DEXA import cancel** interacts with the system document picker, which runs out-of-process; it uses a 10s wait for the picker's `Cancel` control rather than a fixed sleep.
- The chaos monkey denylists destructive/external-surface controls by both accessibility identifier and label substring (delete, log out, sign out, restore purchases, subscribe, manage subscription, connect health, camera, continue with Apple, and anything that opens a system sheet). If a new destructive control ships without one of those labels, add its identifier to `ChaosMonkeyUITests.denylistedIdentifiers`.
- **A shared dev simulator/device can hand a fresh `launch()` a stale screen.** Both suites' `launch()`/`relaunch()` have landed directly on `world_class_screen_metricDetail` (a pushed "Weight" detail with a live Back button) instead of the fixture's intended root, immediately after a full `terminate()` + `launch()` — the account's own state outlives the process. Both suites now call a `popToRootIfNeeded` that pops up to five pushed screens whenever that one identifier is present, scoped narrowly so it never touches a fixture (like ChatFirst) that deliberately opens off the timeline root.
- **`waitForTimelineRoot`'s first post-launch wait runs at 30s, not 12s, and fails with diagnostics.** A real device under notification-banner pressure was seen timing out at 12s with no record of what was actually on screen. `ChaosEdgeCaseUITests.assertTimelineRootAppears` wraps it: on timeout it attaches the full element tree and fails naming every `world_class_screen_*` identifier found, so a red run says what screen it landed on instead of just "false".
- **Settings navigation goes through two different overlays depending on `HomeV2Policy`** — the legacy `PhotoTimelineNavigationMenu` (`photo_timeline_menu_settings`) or the HomeV2 sidebar (`home_v2_sidebar_settings`), neither of which is guaranteed by a given fixture. `waitForSettingsMenuEntry`/`waitForMenuOverlay` check both identifiers before falling back to a label-based `Settings` lookup, and `openPhotoTimelineMenu`'s overlay wait accepts either surface.
- **Two "Retry" controls with similar names cover different chat failures** (`MainTabView.swift`): `chat_reload_button` appears when the initial conversation *load* fails (`isConversationLoadRetryAvailable`, what `-lybUITestChatOfflineFixture` exercises); `chat_retry_button` only appears after a failed message *send* (`failedTurn != nil`). Picking the wrong one silently times out.
- **`integrations_bulk_photo_import_link`'s accessibility identifier is concatenated by SwiftUI** — the on-device tree shows `integrations_bulk_photo_import_link-integrations_bulk_photo_import_link-integrations_bulk_photo_import_link` on the tappable row, so an exact bracket match (`app.buttons["integrations_bulk_photo_import_link"]`) never matches; `testPhotoPermissionRecoveryCopyMatchesCurrentAuthorizationState` matches on `identifier CONTAINS` instead.
