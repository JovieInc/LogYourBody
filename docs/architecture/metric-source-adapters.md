# Metric source adapters (LYB-244)

`MetricSourceAdapter` is the native ingestion contract. Capabilities default to
false. `MetricSourceScheduler` selects delivery modes solely from these flags;
account ownership, permissions, feature gates, entitlement and cost remain
separate admission checks. An unsupported trigger performs no provider work.

| Adapter              | pushEvents | incrementalPull | scheduledPoll | manualUpload |
| -------------------- | ---------- | --------------- | ------------- | ------------ |
| BodySpecDexaImporter | false      | true            | true          | false        |
| HealthKitManager     | true       | true            | false         | false        |

## BodySpec capabilities (LYB-246)

No BodySpec user or partner token was available, so nothing below is a live
call. The finding is the public OpenAPI document loaded by the
[Scalar reference](https://app.bodyspec.com/docs) from
`https://app.bodyspec.com/openapi.json`, retrieved 2026-11-01 (OpenAPI 3.1.0,
info.version 0.20.0, SHA-256
`fb531c62157e0ac2061aa43c65d67ed5a4a528608431cafcc4591f038b40662a`). The API
description calls the surface early-access. The
[decision record](../../packages/shared-lib/decisions/bodyspec-event-support.json)
locks these facts. The existing REST client and atomic DEXA importer remain
the single implementation.

**Push.** Partner webhooks are documented. Creating one is
`POST /api/v1/partners/{partner_id}/webhooks` with partner Basic auth
(`partner_id:partner_secret`). One registration subscribes to one of
`results_ready`, `reservation_created`, `reservation_canceled`, or
`reservation_no_show`. `results_ready` is at-least-once, including another
delivery when the same scan is re-analyzed. Dedupe on `data.result_id`.
`event_id` changes across repeats. An optional secret is standard-base64
encoded into `Authorization: Bearer`. Registration can return 503,
`Webhook system not configured`. The user OAuth surface
(`/api/v1/users/me/...`, scopes `openid`, `profile`, `email`) has no
subscription, callback, or event stream. The document does not mention MCP
events. `BodySpecDexaImporter` keeps `pushEvents` false. A connected user
account is not push delivery. Partner push stays off until a partner account
can register a webhook and a delivery is observed.

**Incremental pull.** `GET /api/v1/users/me/results/` lists the authenticated
user's results. Query parameters are `page` (default 1) and `page_size`
(default 20, maximum 100). The response includes `pagination.has_more`.
There is no cursor, `updated_since`, or `start_time` filter on this list.
Each summary has `start_time`, `create_time`, and `update_time`. The adapter
keeps walking pages and applies `replay(from:)` to `start_time` locally. It
does not assume order or a server cursor. Appointment listing does expose
`start_time` and `reserve_time` filters. Those routes are not the DEXA result
feed. The current client stops a short page (`count < pageSize`) and does not
read `has_more`.

**Rate limits.** The document defines no quota, no 429, no `Retry-After`, and
no rate-limit header. No numeric limit is published. Response headers were
not observed.

**Decision.** The unanswered default is adopted: no test account, so ship
polling only. Supported delivery is incremental pull when a connected
BodySpec session is opened with the app, plus one daily `scheduledPoll` of
the same replay. This slice does not install that app-open caller, a
background timer, or an event endpoint. The Sync action remains the
production incremental-pull caller. `scheduledPoll` stays admitted for a
later caller. Revisit partner webhooks only with partner credentials.
Published webhook docs are not MCP events and do not turn `pushEvents` on.

HealthKit uses its existing observer queries for push delivery.

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
