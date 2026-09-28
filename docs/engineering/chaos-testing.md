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

1. **Crash** — `app.state` left `.runningForeground` unexpectedly, or the process is gone in the screenshot/tree dump. Highest priority; check `~/.codex/goals/lyb-chaos/results/*.xcresult` diagnostics report for a crash log.
2. **Hang** — an element query exceeded the 10s threshold. Note which screen/step; look for a synchronous call on the main thread near that surface.
3. **Dead tap** — the monkey tapped a hittable, non-denylisted control and nothing happened (compare the screenshot before/after the same step in the tree dump). Usually a missing gesture handler or a control that's visually enabled but functionally disabled.
4. **Layout clip** — an element's frame extends outside the window bounds, or text is visually cut off in a screenshot. See `testVeryLongProfileNameRendersWithoutClipping` for the pattern.
5. **Data loss** — a save that should have persisted didn't (check `testRapidDoubleTapSaveCreatesOneEntry` and `testBackgroundingDuringSaveThenForegroundingPreservesState` first; they target exactly this).
6. **Copy** — a validation or recovery message is missing, wrong, or not plain-language (see `LogWeightFormValidator`/`ValidationService` for the source of truth on weight/body-fat error copy).

File anomalies that recur across seeds or land in a golden-path surface as regular issues; a single non-reproducing anomaly at a random monkey step is lower priority than a targeted edge-case test failing, since the edge-case tests are deterministic and always exercise the same path.

## Known limitations

- **Face ID / passcode lock on the test device blocks most navigation-based tests.** If the device's `biometricLockEnabled` app preference is on (Settings → the "Face ID lock" toggle, identifier `home_v2_settings_face_id`), the app gates its whole `ContentView` behind a LocalAuthentication challenge on every relaunch. XCTest cannot dismiss this: `addUIInterruptionMonitor` explicitly cannot handle it (`com.apple.localauthentication.ax.authentication.alert`; Apple's own log line says "If your test failed after this unhandled interruption, please file a bug"). Symptom: any test past the first screen times out waiting for `photo_timeline_menu`, `home_v2_log_sheet`, or similar, with a `com.apple.localauthentication.ax.authentication.alert` line in the log just before the failure. Fix: on the physical device, open the app, turn off "Face ID lock" in Settings, and re-run; this is a one-time device precondition, not something the harness can clear itself. Confirmed root cause during this harness's own device bring-up on 2026-09-28.
- **Photo permission denial** (`testPhotoPermissionRecoveryCopyMatchesCurrentAuthorizationState`) can't force `PHPhotoLibrary` into a denied state — there's no UI-test fixture for it, and toggling the real device's photo permission is hard to reverse and would affect other concurrent test runs on the same shared device. The test asserts the surface renders (either the scanning UI or recovery copy) without crashing, whatever the device's current permission state happens to be, and documents this here instead of faking coverage.
- **DEXA import cancel** interacts with the system document picker, which runs out-of-process; it uses a 10s wait for the picker's `Cancel` control rather than a fixed sleep.
- The chaos monkey denylists destructive/external-surface controls by both accessibility identifier and label substring (delete, log out, sign out, restore purchases, subscribe, manage subscription, connect health, camera, continue with Apple, and anything that opens a system sheet). If a new destructive control ships without one of those labels, add its identifier to `ChaosMonkeyUITests.denylistedIdentifiers`.
