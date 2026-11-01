# Gym-detection consent and retention (LYB-250)

Recorded: 2026-11-01. Parent: LYB-175.
Status: accepted under LYB-250's explicitly authorized default; no separate human
approval is claimed.

## Decision

Gym detection is optional and requires explicit opt-in for each gym. Store only
probable attendance events, never a raw location trail. Events expire after
14 days. Offer one-tap deletion of all gym-detection data. Background location is
never required to use LogYourBody; declining it leaves manual attendance and the
rest of the product available.

This is a product contract for future implementation, not evidence that location
collection or deletion already exists. The dependent
[geofencing slice](../engineering/gym-geofencing.md) implements this contract.
Attendance states and fatigue/scheduling adaptation remain separate slices.

## Allowed data and purpose

All gym-detection data stays on the current device, scoped to the signed-in
account. This decision authorizes no cloud sync, server ingestion, analytics,
crash-log payloads, model context, or third-party sharing of that data.

| Data                       | Allowed contents                                                                                                                             | Lifetime                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Selected gym configuration | Existing gym reference and display name, user-selected fixed gym center/radius needed to monitor that gym, explicit consent and copy version | While that gym's opt-in is active; delete on revocation, gym removal, sign-out or account deletion |
| Probable attendance event  | Opaque event ID, gym reference, detection time needed for expiry/reconciliation, provenance identifying location inference, state `probable` | 14 × 24 hours from the original detection time, or earlier deletion/revocation                     |

The fixed gym center is a selected place, not a record of the device's position.
Process device location/region callbacks transiently on device. Do not persist
device coordinates, movement paths, raw entry/exit callbacks, dwell histories,
arrival/departure pairs, or inferred workout duration. Do not infer or add gyms
from the user's movements. Exclude detection records and configuration from
device/cloud backups and diagnostic exports; copies must not outlive the source.

An event means only "probable attendance at Gym X." It does not establish a
workout, duration, exercises, sets, fatigue or adherence. Absence of an event does
not establish absence from the gym. The attendance-states slice owns state
transitions; [workout reconciliation](../engineering/workout-reconciliation.md)
owns explicit confirmation. A separately user-confirmed workout may retain its
explicitly supplied facts under its own policy, but must not preserve passive
timestamps or other expired/deleted location evidence.

## Retention and erasure

- Expiry uses the original detection time, not the last read, replay, confirmation
  or sync time. Timezone changes do not extend the window.
- At the expiry boundary, exclude the event from all reads, reconciliation and
  derived attendance state. Purge expired records before use on launch/resume
  and whenever the detection store runs. A suspended device cannot execute a
  purge; delete expired bytes on its next execution before exposing them.
- Delete related cached/derived location evidence and pending work as well as
  stored events. Never retain long-lived attendance aggregates from expired
  location evidence. Deletion/revocation must win over queued callbacks, in-flight
  writes and retries; re-enabling detection cannot restore erased events.
- If a delete fails, keep detection stopped and the affected evidence unavailable.
  Show "Deletion couldn't finish. Gym detection is off. Try again." and offer
  "Try again"; do not report success before persistent deletion completes.

## Opt-in and permission copy

Show this disclosure only when the user chooses detection for a selected gym.
Replace `{gymName}` with that gym's display name. No preselected consent, blanket
onboarding consent, or repeated permission nudges after declining.

**Title:** Detect visits to {gymName}?

**Body:** LogYourBody can use your location, including when the app is closed, to
suggest when you may have visited this gym. Your selected gym and probable visits
stay on this device. Probable visits expire after 14 days. We don't save your
location history. Turn detection off for this gym or delete all gym detection
data in Settings. You can use LogYourBody without location access.

**Primary action:** Enable for this gym

**Secondary action:** Not now

The primary action records per-gym consent and starts the contextual iOS
permission flow. It does not override OS permission. Monitoring starts only when
both consent and the necessary OS authorization are present. Explain any
background-permission upgrade before requesting it; never require that upgrade
for unrelated features. Existing OS authorization does not opt a new gym in.

**Proposed iOS purpose copy for the implementation slice:**

- While in use: "Use your location to detect possible visits to a gym you choose.
  Location access is optional."
- Background: "With your permission, detect possible visits to gyms you enable,
  even when LogYourBody is closed. We don't save your location history."

**Settings toggle per gym:** Detect visits

**Toggle explanation:** Possible visits only. A visit doesn't confirm a workout.
Turning this off deletes this gym's detection data.

## Revoke and delete behavior

| User action                                                | Required result                                                                                                                                                                                                                         |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Decline the disclosure or deny iOS permission              | No monitoring or attendance events. Discard pending detection configuration/consent if authorization is denied. No blocked core flow.                                                                                                   |
| Turn off "Detect visits" for one gym, or remove that gym   | Stop monitoring and cancel pending work for that gym immediately; erase its detection events, saved detection configuration and consent. Other opted-in gyms continue.                                                                  |
| Remove or reduce iOS permission below what detection needs | OS permission takes precedence. On the next authorization check/callback/resume, stop affected monitoring and erase its detection data and consent. Restoring OS permission alone must not restart detection.                           |
| Tap "Delete all gym detection data" in Settings            | One tap stops all gym detection and deletes all detection events, configurations, consent and derived copies for the current account. No second confirmation or reauthentication. Keep the control available with the feature gate off. |
| Sign out or delete the account                             | Stop monitoring, cancel pending work and remove all of that account's local detection data before another account can use the store.                                                                                                    |

**Delete explanation:** Deletes probable visits and saved detection settings for
all gyms on this device, and turns gym detection off. Workouts you confirmed stay.

**Delete success:** Gym detection data deleted. Detection is off.

In-app deletion does not change the iOS permission setting. Any subsequent
detection requires selecting a gym and explicitly opting in again. A feature-gate
shutdown must stop collection without hiding revoke/delete controls or suspending
expiry. A new device starts with detection off.

## Downstream boundary

The [implementation slice](../engineering/gym-geofencing.md) is limited to this
contract and depends on the attendance-states slice. Before enabling collection,
it must update the shared/bundled privacy disclosure and review the App Store
privacy inventory against the implemented data flow. This record does not change
the current [privacy policy](../../shared/legal/privacy-policy.md) or certify
App Store answers. Real-device TestFlight evidence stays with LYB-175.
