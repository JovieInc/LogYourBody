# Training rest timer (LYB-116)

`training_rest_timer_v1` enables the adjustable timer through the existing analytics
port. It defaults off when the gate is absent. The training coach gate still owns
access to the live session. No server schema, endpoint, or training prescription
changes are required.

An acknowledged new set starts rest when unfinished work remains. Starting values
are editable conveniences: 120 seconds for multiple positive muscle contributions
in the existing prescription metadata, 90 seconds otherwise. The timer offers
15-second adjustments within 15–600 seconds. Adjustments preserve elapsed time and
are remembered for that exercise within the session. These values are not readiness
assessments or engine-generated rest prescriptions.

The existing account/session draft journal stores durations, the original start,
and skips. Corrections and session refreshes do not restart rest. A failed or pending
set does not start it. Pausing, ending, completing the workout, or a safety stop
cancels it. Account data deletion uses the journal's existing purge path.

`TrainingRestAlerting` isolates system effects from the model and controls. The
ActivityKit adapter starts a local Live Activity with only timer dates, and the
WidgetKit extension renders a system countdown on the Lock Screen and Dynamic
Island. No account identity, exercise name, or health measurements enter the activity
payload. Previously running activities and pending timer notifications are reconciled
when restarting the adapter after process termination.

At zero, an active foreground session receives one notification haptic. A local
notification handles suspended/background delivery after system notification
authorization; sound and vibration follow device settings. Expired timers never
replay a late haptic. The date-based countdown remains usable when notification or
Live Activity authorization is unavailable. See Apple's
[Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
and [local notification delivery](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
documentation for those platform boundaries.

Closing the live-session screen cancels its activity and alert. Reopening restores
the original countdown deadline, including adjustments and skips. Backgrounding the
app while the session remains open keeps the system countdown and local alert.

The app builds and embeds `LogYourBodyRestTimer` (`com.logyourbody.app.rest-timer`).
Distribution needs a valid profile for that identifier in Match, in addition to the
app profile. Release lanes configure profiles per target and export both mappings;
they must not apply the app's profile as a global Xcode command-line override. The
default extension profile name is `match AppStore com.logyourbody.app.rest-timer`;
`REST_TIMER_PROVISIONING_PROFILE_SPECIFIER` can select an already-installed profile.
No signing credentials or profiles are created by this change.

LYB-310 temporary exclusion: the Match repository has no App Store profile for
`com.logyourbody.app.rest-timer` yet. The `build_release` lane therefore strips the
extension dependency and embed entry from the app target for that archive only, signs
and exports only the app profile, and readonly match syncs request only the app
identifier. The checked-in project graph, Debug/dev builds and the fingerprints above
are unchanged. Once the profile exists (`bundle exec fastlane setup_provisioning
type:appstore readonly:false force:false`), revert the exclusion PR to restore the
two-target release signing described above.

Validation entry points:

- `TrainingSessionDraftTests`: exercise defaults, acknowledgement and retry, final
  set, adjustment/skip restoration, correction/pause, gate fallback, one-shot
  completion, replacement, background completion, stale timers, and ownership.
- `LogYourBodyUITests/testTrainingRestTimerAdjustsAndSkipSurvivesReopening`: production
  controls with isolated fixture effects (`-lybUITestTrainingRestTimer`).
- `python3 scripts/ios/test_training_rest_project.py`: actual build graph, shared
  attributes membership, extension embedding and plists.
- `ruby scripts/ios/test_training_rest_release.rb`: actual release lane with
  instrumented external actions, including default and explicit profile names.
  Both scripts also run in the shared library's existing required test suite.

Linux lint and packaging tests do not replace native acceptance. Before rollout,
run the native Unit selector and the UI case at the final commit, retain the required
execution/coverage receipts, verify a signed archive, and check Live Activity and
haptic behavior on an iPhone (foreground, locked/background, disabled authorization,
adjust/skip, relaunch, and session completion).
