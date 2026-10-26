# Metric source adapters (LYB-244)

`MetricSourceAdapter` is the native ingestion contract. Capabilities default to
false. `MetricSourceScheduler` selects delivery modes solely from these flags;
account ownership, permissions, feature gates, entitlement and cost remain
separate admission checks. An unsupported trigger performs no provider work.

| Adapter              | pushEvents | incrementalPull | scheduledPoll | manualUpload |
| -------------------- | ---------- | --------------- | ------------- | ------------ |
| BodySpecDexaImporter | false      | true            | true          | false        |
| HealthKitManager     | true       | true            | false         | false        |

BodySpec event support is unverified. Its existing REST client and atomic DEXA
importer remain the single implementation. The Sync action uses incremental
pull. Polling callers use the same scheduler and replay operation; this slice
does not install a background polling timer or an event endpoint. HealthKit
uses its existing observer queries for push delivery.

`replay(from:)` accepts an inclusive start date or nil for all available history.
BodySpec filters the provider's report `start_time` while continuing through all
pages, without assuming ordering or an undocumented server cursor. HealthKit
uses the existing historical query/batch importer with the supplied start date.

BodySpec's idempotency key is the unchanged provider result ID. Its existing
transaction scopes that ID to the authenticated account and `bodyspec` source,
checks both persisted rows, and commits the metric/result pair atomically.
Repeats preserve IDs, measurement values, report timestamps, pending sync state and
sync triggers. No second dedup ledger or schema migration is needed. HealthKit
uses sample UUIDs in its existing source metadata and reconciliation.

`checkEntitlementAndCost()` is a throwing, side-effect-free admission hook.
The scheduler calls it before replay, and direct replay also enforces it.
BodySpec rechecks the injected guard together with connection/session admission
before requests and inside the atomic write. The default hook adds no billing
policy; composition code can supply entitlement or request-budget checks.
Existing gates and account/connection checks still apply.

`lastSuccessfulSync` is an account-scoped completion receipt in local defaults,
not a provider measurement date. BodySpec updates it only after a complete,
failure-free replay, including successful empty and duplicate-only runs. Failed,
cancelled, denied or superseded runs preserve the previous receipt. HealthKit
records successful recent, incremental and historical body-metric imports and
anchored smart-scale reconciliation. Persistence failures fail the run instead
of producing a receipt.
Legacy observer cooldown timestamps are kept separate.

`MetricSourceAdapterTests` uses a fake adapter and the existing recorded JSON
fixtures from `BodySpecAPITests`, with local Core Data and no provider network.
The suite is registered in the native test target and included by the Unit plan.
Native execution and coverage require the repository's macOS runner; real-device
TestFlight evidence remains with LYB-171.
