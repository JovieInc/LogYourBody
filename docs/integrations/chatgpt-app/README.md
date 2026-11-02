# LogYourBody product API and MCP integration

One remote MCP server exposes actions to read the user's LogYourBody hypertrophy plan and log
sets. Client and voice availability require independent qualification against that endpoint
and its per-user OAuth flow. Tracking issue: LYB-108 (epic LYB-107).

LYB-161 extends the planning contract to
every iOS capability. The inventory below distinguishes checked-in adapters from
pending parity and client qualification; it does not certify deployed access.
The [roadmap feature contract](../../product-development-roadmap.md#product-api-and-mcp-parity--lyb-161)
and release exception apply. This documentation-only intake grants no runtime,
provider connection, release, or marketplace authority.

## Surface

| Item                 | Value                                                                                                          |
| -------------------- | -------------------------------------------------------------------------------------------------------------- |
| Endpoint             | `POST https://www.logyourbody.com/api/mcp` (stateless Streamable HTTP, JSON responses)                         |
| Resource metadata    | `/.well-known/oauth-protected-resource/api/mcp` (RFC 9728), alias at `/.well-known/oauth-protected-resource`   |
| Authorization server | Jovie Better Auth issuer `https://jov.ie/api/auth`                                                             |
| Scopes               | `lyb:training.read`, `lyb:training.write`                                                                      |
| Flags                | `LYB_CHATGPT_MCP_ENABLED=true` and `LYB_HYPERTROPHY_COACH_API_ENABLED=true`; otherwise every route answers 404 |
| Code                 | `apps/web/src/lib/mcp/`, `apps/web/src/app/api/mcp/`                                                           |

Tools:

| Tool                      | Scope | readOnly | destructive | openWorld |
| ------------------------- | ----- | -------- | ----------- | --------- |
| `get_todays_workout`      | read  | true     | false       | false     |
| `log_sets`                | write | false    | false       | false     |
| `log_session_feedback`    | write | false    | false       | false     |
| `get_training_progress`   | read  | true     | false       | false     |
| `control_workout`         | write | false    | false       | false     |
| `correct_set`             | write | false    | false       | false     |
| `swap_exercise`           | write | false    | false       | false     |
| `revise_training_program` | write | false    | false       | false     |

This is the training source inventory. `revise_training_program` additionally
requires the delegated-programming gate. Weight and health-vault tools have
separate gates, scopes and consent boundaries described below; training scopes
do not authorize them. The executable list is
[`list-tools.ts`](../../../apps/web/src/lib/mcp/list-tools.ts).

`log_sets` only adds sets. It never overwrites a logged set and never logs beyond the
engine's plan, so `destructiveHint: false` is accurate. It previews the plan before
starting a session, so a misheard exercise name writes nothing. The shared set writer
atomically keeps the first saved value for a session/exercise/set identity. Identical
retries return that original record; different values return `set_conflict` (HTTP 409
on the mobile route). A correction requires a separate, explicit update contract.

Recovery check-ins contribute one latest observation per session, including legacy
records and concurrent duplicate writes. Repeating that session's latest identical
scores returns the original check-in and observation time; changed scores remain a
valid update, including updated pain reports. Without a durable client request ID,
a differing retry after that same session was updated is indistinguishable from a
new change. Durable request identity and correction history remain LYB-123 work;
this does not claim exactly-once feedback storage.

When the newest check-ins share a timestamp, the higher pain report takes precedence
so uncertain ordering cannot discard the existing pain stop. For a single session,
contradictory scores at the same observation time remain unchanged in storage and
responses, but cannot establish a confirmed multi-session decline until the recovery
feedback is clarified. This does not freeze progression from logged sets. Identical
duplicate scores are not ambiguous evidence.

Every number the training tools return comes from the deterministic training engine or from the
user's own logs. Enrollment, adult confirmation and the safety consent stay in the iOS app;
an unenrolled account gets a pointer to the app instead of a plan.

## Token checks

Each request must carry `Authorization: Bearer <JWT>`. The server verifies, on every request:

- EdDSA (Ed25519) signature against `https://jov.ie/api/auth/jwks`, cached 10 minutes, one
  refetch for an unknown `kid`. Any other `alg` is rejected.
- `iss` equals the issuer exactly.
- `aud` contains the resource URL. Production pins it to
  `https://www.logyourbody.com/api/mcp`; it never follows the request Host header there.
- `exp` and `nbf` with 30 seconds of skew; `sub` present.
- The tool's scope is in `scope`. A missing scope returns a tool error with
  `_meta["mcp/www_authenticate"]` carrying `error="insufficient_scope"` so ChatGPT can
  ask the user to reconnect.

No shared secrets: the server holds no client secret and never calls the issuer except to
fetch public keys.

## Production prerequisites (Jovie issuer, not in this repo; JOV-7796)

The live issuer metadata (checked 2026-10-04) supports PKCE S256 and the RFC 9207 `iss`
response parameter, signs with Ed25519, and advertises only
`openid profile email offline_access`. It has no `registration_endpoint` and no client ID
metadata document support. Before production:

1. Register the resource `https://www.logyourbody.com/api/mcp` so a `resource` parameter on
   authorize and token requests yields a JWT access token with that `aud`.
2. Add the scopes `lyb:training.read` and `lyb:training.write`, consented on the Jovie
   consent page with plain wording ("Read your LogYourBody training plan and progress",
   "Log sets and check-ins to LogYourBody").
3. Give ChatGPT a client. Recommended: one pre-registered public client
   (`token_endpoint_auth_method: none`, PKCE) with redirect
   `https://chatgpt.com/connector_platform_oauth_redirect`, entered in the ChatGPT app
   settings. Alternatives: turn on dynamic client registration
   (`FEATURE_OVIE_MCP_DYNAMIC_CLIENT_REGISTRATION`, affects every MCP client) or add client
   ID metadata document support.

## Local verification

Unit and route tests: `pnpm --filter apps/web exec jest src/app/api/mcp`.

End to end with the official MCP TypeScript SDK client (the transport the MCP Inspector
CLI uses): serve `createMcpRouteHandlers` from a small Node HTTP harness with the in-memory
records port (`apps/web/src/lib/training/memory-records.testing.ts`) and a throwaway
Ed25519 key, mint a token with `aud=http://localhost:8787/api/mcp`, then connect a
`StreamableHTTPClientTransport` client and call each tool. Receipts from 2026-10-04 are in
the PR description.

## ChatGPT

- Developer-mode candidate setup: add `https://www.logyourbody.com/api/mcp` in the client's
  app settings after the issuer prerequisites and hosted-client policy review pass. Verify
  metadata discovery, per-user OAuth and tool listing in the actual client/version; this
  procedure is not a successful connection receipt.
- Voice: tool availability is pending an actual ChatGPT voice-mode test. Training inputs
  accept loose exercise names and `weightUnit: "lb"` converted to kilograms on the server,
  with set numbers filled in automatically; those schemas do not prove voice execution.
- Submission package: [`submission.md`](submission.md).

## Grok

Grok calls the same training server. The health vault view is ChatGPT-only. On Grok the vault
surface is the opt-in share tool, and only after a confirmation minted in the vault view.

- Consumer: grok.com, Connectors, New Connector, Custom, paste the endpoint URL. xAI joined
  Voice Mode to Connectors in August 2026 (third-party report; verify on device).
- API: the Voice Agent API and Responses API accept a remote `mcp` tool with `server_url`.
- Work needed: confirm Grok's OAuth redirect URI and add it to the Jovie MCP redirect
  allowlist (`apps/web/lib/oauth/mcp-redirect-allowlist.ts` in the Jovie repo, which today
  allows ChatGPT, Claude, Cursor, VS Code and loopback), then register a Grok client the same
  way as ChatGPT. Tracked in LYB-121.

## Muse

Muse is an agent in the Jovie fleet (agent mesh roster). Its runtime spec is unverified. If
it has a remote MCP client it adds the same endpoint and runs the same per-user OAuth flow.
Without a widget it gets the opt-in share tool only, same as Grok.
It must never use a shared service token to log on a user's behalf. Tracked in LYB-122.

## What stays out

GLP-1 data and anything medical stay out of this server. Body composition and progress
photos are not in MCP tool results. When the health vault gate is on, a ChatGPT widget can
open a view that loads those measurements directly from LogYourBody, and
`share_summary_with_chatgpt` returns only the fields the user confirms. The manual weight
lifecycle below is a separate write and read of weights the user submits. It is not the vault.
OpenAI bans protected health information, limits sensitive data to what the app strictly
needs, and lists Ozempic under prohibited commerce.

## Health vault (LYB-330)

Default off. `LYB_HEALTH_VAULT_ENABLED` and `LYB_CHATGPT_MCP_ENABLED` must both be true, and
either `LYB_HEALTH_VAULT_GATE_OVERRIDE=on` or an injected evaluation of `health_vault_chatgpt`
must be open. A missing evaluation stays closed. Training and weight flags do not open it.

`open_health_vault` is listed only for the ChatGPT widget client (`azp` `chatgpt`). Its tool
result is readiness, item counts, and a single-use five-minute handle in tool-result
`_meta`. Measurements are not in `content`, `structuredContent`, or `_meta`. The widget
exchanges that handle with `POST /api/health-vault/view` on this host and loads images from
LogYourBody. Grok, Muse, and Claude list only `share_summary_with_chatgpt`. That tool returns
a summary after the user confirms the fields in the vault view. The confirmation is a consent
event. The model cannot mint the confirmation itself.

`_meta` is hidden from the model and still passes through the assistant host. A handle there
does not mean the host never saw it. Counts in the tool result are included because the
product example uses them, and legal has not accepted them yet.

Listing and marketing copy are blocked on legal review. Do not publish either sentence until
that review lands:

- Candidate, only if the payload, network, and transcript audits pass: "Your scans, photos and weigh-ins load straight from your LYB vault. They never pass through OpenAI, and ChatGPT's AI never sees them unless you choose to share."
- Otherwise, and on any surface without a widget: "Your scans and photos stay in your LYB vault. ChatGPT only sees what you choose to share."

The sentence "OpenAI never sees your health data" is not approved. Typed messages and
confirmed shares do reach the assistant host.

Before every listing republish, run:

`pnpm --filter apps/web exec jest src/lib/mcp/health-vault/payload-audit.node.test.ts src/lib/mcp/health-vault/widget.test.ts --coverage=false`

The live transcript export (ChatGPT developer mode, ten conversations) needs a developer
login and is not part of CI. The checked-in fixtures cover the same assertion.

## First implementation slice: manual weight lifecycle

LYB-162, the first slice of LYB-161. Product HTTP and the official MCP client share one
domain action for `create_weight_entry`, `list_weight_entries`, `correct_weight_entry`,
and `delete_weight_entry`. Native and Siri use the same validation, record identity,
revision, and operation id through `BodyMetricLoggingService` and `LogWeightIntent`.
There is no second Siri runtime. Body-fat intents stay out of this slice.

The actions default off. `LYB_METRICS_AGENT_ENABLED` and `LYB_CHATGPT_MCP_ENABLED` must
both be true, and either `LYB_METRICS_AGENT_GATE_OVERRIDE=on` or an injected Statsig
evaluation of `metrics_agent_weight_lifecycle` must be open. A missing evaluation stays
closed. `lyb:training.read` and `lyb:training.write` do not authorize these tools.
`lyb:metrics.read` and `lyb:metrics.write` are enforced on every call and are not
registered at the Jovie issuer until JOV-7796 is extended. Each call also requires an
explicit `metrics_agent_grants` row for that subject: connected, consented, entitled,
not revoked, and not deleted. A missing row is unconnected. Tokens are resource-bound
to the MCP audience. There is no shared service identity.

Input is an explicit number plus `kg` or `lb`. The server does not guess a unit or
round a pound value to two decimals. Pounds use `0.45359237` in integer milli-units.
The measured timestamp must carry an offset, and `utc_offset_minutes`, `local_date`,
and the IANA zone must describe that same instant. Same-day rows stay distinct.
Create, correct, and delete take a stable operation UUID. The same operation and
payload replay the original receipt. A different payload for that operation conflicts
and writes nothing. Correct and delete require `expected_revision`. A stale revision
conflicts. A delete leaves a tombstone. A later read of that id returns the tombstone;
a list of live rows does not.

A native push does not assign `deleted_at = null`. A push onto a tombstone, a stale
payload, or a different payload at the same client time is a conflict. A strictly
newer client time is kept as an offline edit. The HTTP and MCP receipt reports
`cloud.status = committed` and `device.healthkit = not_claimed`. It does not say an
Apple Health sample was written, corrected, or deleted.

HTTP lives at `POST/GET /api/metrics/weight`, `POST /api/metrics/weight/corrections`,
and `POST /api/metrics/weight/deletions`. The gate answers 404 before authentication.
Account deletion removes `weight_operation_receipts`, `body_metric_audit`, and
`metrics_agent_grants` before `body_metrics`. Acceptance is
[agent parity acceptance — October 13, 2026](../../USER_JOURNEYS.md#agent-parity-acceptance--october-13-2026).

## Canonical iOS capability inventory

Original inventory anchor: main `bf05b7175bb3d8c8e8c6c24e29b11d301c70299e`.
Reconciled against main `94d019ba1c0507cfe122a183e0c8df621e160b1f` on October 31, 2026. Paths below are source evidence, not deployment or successful user-journey
receipts. “Gap” means a focused product contract or adapter is still needed; it
does not authorize exposing a native sync collection as an agent tool. Keep this
inventory current in each new/materially extended feature's specification and PR.

Native service paths are relative to `apps/ios/LogYourBody/`; HTTP paths are under
`apps/web/src/app/api/`. All proposed mappings inherit the roadmap's subject,
consent, entitlement, provenance, revision, retry and completion requirements.

| iOS capability and source anchor                                                                                                                                                                              | Existing HTTP/MCP source                                                            | Required product action or truthful boundary; remaining gap                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sign in, onboarding, consent, sign out: `Services/AuthManager.swift`, `Services/OnboardingStateManager.swift`                                                                                                 | `auth/mobile/session`, `auth/mobile/profile`; MCP bearer verification               | Read LYB connection/permissions; connect, revoke and reconnect through explicit per-client OAuth/user consent. Device sign-in and onboarding confirmations remain user handoffs. Identity is not consent; qualification pending.                                                                                                                         |
| Manual weight history/create/edit/delete: `Services/BodyMetricLoggingService.swift`, `Services/BodyMetricAppIntents.swift`                                                                                    | `metrics/weight`, corrections/deletions; four weight tools above                    | LYB-162 source exists behind closed gates. Preserve owned record and operation IDs, atomic receipts, revisions/tombstones and native reconciliation. Real client/device acceptance remains pending.                                                                                                                                                      |
| Body-fat and other composition records; imported-value correction/exclusion/undo: `Services/BodyMetricLoggingService.swift`, `Services/MetricCorrectionService.swift`                                         | `body-metrics`, native body-metrics sync; no equivalent delegated lifecycle         | Gap: typed read/create/correct/delete and overlay/undo contracts that retain original source evidence. `LogBodyFatIntent` is local; correction/delete intents are absent. Weight scopes do not grant composition access.                                                                                                                                 |
| Latest metrics, history, deterministic trends, interpolation, body score: `Services/MetricsInterpolationService.swift`, `Services/BodyScoreRecalculationService.swift`, `Services/TimelineDataProvider.swift` | Weight listing; gated health-vault view/confirmed summary; no general trend tool    | Gap: deterministic read summaries with dates, units, method/version, missingness and provenance. `ShowLatestMetricsIntent` reads local state. Timeline navigation/visual rendering may hand off to the app; no invented calculations or automatic health disclosure.                                                                                     |
| Profile, units, goals, dated outcomes and preferences: `Views/PreferencesView.swift`, `Services/DatedOutcomeStore.swift`                                                                                      | `auth/mobile/profile`, `auth/mobile/dated-outcome`; no equivalent MCP actions       | Gap: read/update/reset selected targets and preferences through validated domain actions with revisions and explicit units/timezone. Keep estimates and targets distinct; preserve safety restrictions and device-local settings boundaries.                                                                                                             |
| Progress photos: capture/select, attach, review, edit/delete, bulk import: `Services/PhotoUploadManager.swift`, `Services/PhotoLibraryScanner.swift`, `Views/ProgressPhotoAttachSheet.swift`                  | `auth/mobile/photos`; gated vault media/view and confirmed shares                   | Gap: owned photo/import job actions, source/measurement association, retry and deletion/readback contracts. Camera/library selection and local processing need device permission and completion receipts. Never put raw photos into ordinary MCP results.                                                                                                |
| Illustrative Home wireframe when no photo is available: `Components/WireframeAvatarStage.swift`, `Components/WireframeAvatarFamily.swift`, `Resources/WireframeAvatarFamily.json`                             | No HTTP and no MCP tool. Device-local drawing only.                                 | Explicit male or female preference stored on the device. Adiposity, muscularity, and frame are illustrative settings, not body-fat or FFMI. Anny and SMPL-X are not bundled. Missing measurements do not invent a body-fat value.                                                                                                                        |
| Optional personal outline from a front or side capture: `Components/PersonalBodyEstimate.swift`, `Components/PersonalBodyEstimateStore.swift`, `Components/PersonalBodyStage.swift`                           | No HTTP and no MCP tool. Device-local drawing only. External processing is refused. | A supported front or side can adjust the on-device outline for that date. The outline is not body fat or a weekly change. A refused or failed fit leaves the photo timeline usable. Derived outlines delete with the photo and the account.                                                                                                              |
| DEXA/InBody/PDF and BodySpec imports: `Views/DexaPDFImportSheet.swift`, `Services/BodySpecDexaImporter.swift`, `Services/BulkImportManager.swift`                                                             | `parse-pdf`, `parse-pdf-v2`, native sync; no equivalent delegated import lifecycle  | Extend LYB-80: explicit source authorization/upload, preview/confirm, dedup, correction and persisted import readback. Device-scoped BodySpec credentials do not prove a per-user cloud connection. Parsing/skipped counts alone are not successful ingestion.                                                                                           |
| Apple Health weight/body-fat/steps import and supported writes: `Services/HealthKitManager.swift`, `Services/HealthSyncCoordinator.swift`                                                                     | Native sync; no remote HealthKit execution                                          | Device handoff for authorization, import/write and permission management. Report supported data, observed samples and individual effects; cloud mutation never proves Apple Health changed. Permission-request completion does not prove read access.                                                                                                    |
| Daily records/steps and GLP-1 dose/check-in history: `Models/DailyMetrics.swift`, `Models/Glp1DoseLog.swift`                                                                                                  | Native collection sync; no delegated product actions                                | Gap: separate owned read/create/correct/delete contracts, units/observation times and provenance. GLP-1/medical records remain excluded from this MCP server; use an authorized native handoff until a separately approved health-data contract exists.                                                                                                  |
| Training enrollment, plan, sets, corrections/undo, session control/feedback, swaps, progress and program steering: `Services/TrainingService.swift`                                                           | `auth/mobile/training/v1`; training tools above                                     | Extend LYB-108/123 using existing owners/branches and additive logging. Enrollment/safety consent stays in app. Audit remaining mobile-only actions (including alternatives, recovery trials and optimizer/canvas flows) before claiming full parity. Only engine-returned numeric prescriptions; explicit corrections never overwrite additive creates. |
| Chat, voice input, spoken replies: `Services/ChatService.swift`, `Services/VoiceCaptureService.swift`                                                                                                         | `auth/mobile/chat/v1`, `auth/mobile/voice/v1`; MCP calls the underlying actions     | Extend LYB-38. Separate action selection from argument extraction; both use the same validated action boundary. Microphone permission/capture and audio playback need native/provider receipts; transcript or TTS delivery does not prove a mutation.                                                                                                    |
| Reminders, training rest timers/alerts and system controls: `Services/NotificationManager.swift`, `Services/TrainingRestAlerts.swift`, `Services/TrainingRestTimer.swift`                                     | No equivalent delegated device executor                                             | Gap: read/set/cancel preference actions plus explicit device handoffs for notification authorization/scheduling and local timers. A saved preference is not delivered notification evidence; unavailable device effects remain pending.                                                                                                                  |
| Purchases, restore, subscription/account management: `Services/RevenueCatManager.swift`, `Views/PreferencesView+SecuritySubscriptionSection.swift`                                                            | RevenueCat webhook and profile entitlement state; no MCP purchase                   | Read verified entitlement state where permitted; StoreKit purchase/restore and system subscription management are user/system handoffs. No agent purchase or entitlement bypass. Completion requires verified transaction/entitlement readback.                                                                                                          |
| Biometrics and app lock: `Views/BiometricLockView.swift`                                                                                                                                                      | No remote biometric operation                                                       | Local authentication/settings handoff. Never report a remote token as device unlock or infer biometric success; require device confirmation without biometric data in the tool payload.                                                                                                                                                                  |
| Export, metric/photo sharing, account deletion: `Views/ExportDataView.swift`, `Services/BodyScoreShareExport.swift`, `Views/PreferencesView+AccountSection.swift`                                             | `auth/mobile/export`, `auth/delete-account`; no delegated export/erasure tools      | Gap: explicit consent/confirmation, subject-scoped export or deletion request/status and durable completion receipts. Native share sheet/file delivery is a device handoff. Revoke/delete must prevent in-flight retries or offline pushes restoring erased data; respect retention and health-data policy.                                              |
| Integration availability, connection, permissions, sync status, support: `Views/IntegrationsView.swift`, `Services/BugReportManager.swift`                                                                    | Native adapters; no MCP integration-status action                                   | Extend existing [integration-status semantics](../../architecture/native-integration-status.md): distinguish configuration, per-user connection, permission, history and last verified sync/error. Reconnect/revoke and support submission require explicit user action; opening a link is not provider completion.                                      |

### Execution-boundary handoff contract

For every device/system/user handoff, specify the requested action, authenticated
subject and owned resource, necessary permission/confirmation, target surface and
how the user resumes. A returned link or accepted request means only that the
handoff was offered. Keep denied, cancelled, unavailable, pending and completed
outcomes distinct. Claim completion only after a correlated device/provider
receipt and persisted readback of the intended effect. If that readback is not
available, say it remains unverified and give the user the next supported step.
Do not invent a deep link, remote device executor or permission grant.

Core Data remains the native/offline authority. Cloud results do not certify a
device has reconciled; device saves do not certify cloud commitment. Carry record,
operation and revision identities through sync, account switch, retries and
tombstones. An intentional second entry gets a new operation ID even with the
same value/date. A retry keeps its ID; correction/delete targets the owned
measurement and expected revision, never another create.

## Entry-point-to-action mapping — October 13 clarification

Prefer cheap maintained adapters before knowing which entry point wins. Reuse
`LogWeightIntent`, `LogBodyFatIntent` and `ShowLatestMetricsIntent` through
[`BodyMetricLoggingService`](../../../apps/ios/LogYourBody/Services/BodyMetricLoggingService.swift);
native controls, Siri, HTTP, MCP and any justified CLI must preserve the same
product action semantics rather than introduce another runtime.

| Product action level | Native/Siri source and gap                                                                                    | Product API / MCP mapping                                                                                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read latest/history  | `ShowLatestMetricsIntent` reads local weight/body fat; freshness/cloud state needs explicit mapping           | Weight list with owned record/date filtering exists; broader latest/trend reads remain scoped gaps. Local body-fat access does not authorize MCP disclosure.                                         |
| Create weight        | `LogWeightIntent` → `BodyMetricLoggingService`; source now assigns record/operation UUIDs per intent instance | `POST /api/metrics/weight` → `create_weight_entry`, same owned measurement/retry semantics. Intent reconstruction/resume must prove stable identity on device.                                       |
| Create body fat      | Existing `LogBodyFatIntent` → same logging service                                                            | Future composition action only after its separate validation, identity, consent and receipt contract passes. No new metrics scope inferred.                                                          |
| Correct / delete     | Native record editing exists; dedicated correction/delete App Intents are absent                              | Weight correction/deletion routes → `correct_weight_entry` / `delete_weight_entry`; use owned ID, expected revision and stable operation ID. Extend intents only after corresponding contracts pass. |
| Device/system effect | Existing native permission, purchase and capture controls                                                     | Offer explicit handoff/status actions; report completion only at the actual execution boundary.                                                                                                      |

At the October 13 anchor, intents lacked explicit date/operation inputs. Current
weight source adds per-instance IDs; the intents still expose no measurement-date
or operation-ID parameters, and body-fat has no equivalent explicit identity.
Do not claim durable Siri retry/resume or cloud completion from a local dialog.
Contracts must preserve authenticated subject, measurement identity, validation,
units, date/zone/provenance and truthful local/pending/cloud/conflict/device states
in UI, spoken dialog, structured result and JSON.

“MCP events” adds no LYB standard. The
[`handler`](../../../apps/web/src/lib/mcp/handler.ts) implements `initialize`,
`ping`, `tools/list` and `tools/call`; current source also supports the gated vault
resource view through `resources/list` and `resources/read`. It advertises
`tools.listChanged=false` and returns stateless JSON POST results; GET is 405 when
enabled. There is no SSE resume or domain-event subscription. `structuredContent`
is a result payload. Protocol notifications are neither mutation commands nor
durable completion receipts. Future notifications require negotiated capabilities
and the same action/receipt identities.

Order: weight action/receipt fixtures and boundary → existing weight/latest
intent plus HTTP/MCP adapters → body-fat/correction/delete intents after their
contracts pass → thin CLI only for a measured scripting gap. Independent adapters
need not wait for every client. Full-duplex Siri through AirPods is a founder
hypothesis, not a verified Apple announcement or an available dependency.

## Client qualification and focused backlog contracts

LYB-163's [qualification matrix, receipt protocol and adopt-first CLI decision](client-qualification.md)
make the following contract actionable. All client acceptance remains pending; the decision
is to use existing official tooling first and build no product CLI without a repeated gap.

Extend LYB-162 for the weight lifecycle
and LYB-163 for client qualification.
Qualify **Claude Code, ChatGPT and Jovie independently**: supported transport,
per-user OAuth/resource audience, explicit LYB connection/consent, read/write
permissions, revoke/reconnect, lost-response retry, persisted mutation readback,
and native reconciliation. A shared Jovie `sub`, local SDK harness or another
client's success does not qualify a client. All three remain unverified here.
Adopt the official MCP client/Inspector for protocol conformance and dogfood;
record client/version, exact source revision, environment, action/receipt IDs,
scope/grant state and privacy-safe readback evidence per the
[completion evidence contract](../../USER_JOURNEYS.md#agent-parity-completion-evidence).

Compose existing first-party routes, typed actions, ports and adapters. No new
durable agent platform or universal runtime. A CLI is a thin optional adapter
only when LYB-163 documents a reproducible scripting gap and maintenance value.
Plugin/marketplace availability is packaging with separate provider approval;
it neither grants OAuth access nor proves a working connection. Coordinate
issuer audience, consent, scope and client registration with
JOV-7796; do not register/connect accounts
from this planning lane. Mira Thud remains an unverified research candidate with
no available public API or verified weights dependency; no model/runtime is selected.

Split the remaining gaps into focused contracts as the existing features are
extended. These are backlog candidates, not newly dispatched issues or blockers.
LYB-274 authorizes only a CI parity-inventory check after the current TestFlight
release ships. Feature slices stay unauthorized. The
[recorded slices](../../../packages/shared-lib/decisions/agent-parity-slices.md)
are repository-local keys for the inventory check, goals/preferences, trends,
photos/imports, GLP-1, export/deletion and integration status.
LYB-275 qualifies Claude Code first on a synthetic fixture account only, then
ChatGPT, then Jovie. Real consented accounts and client registrations are not
provided. The
[qualification order](../../../packages/shared-lib/decisions/client-qualification-order.md)
names fixture-a and fixture-b and creates one repository-local slice per
client. It connects no account and registers no client.

| Contract / existing lane                             | Trigger and KPI                                                                                           | Required acceptance before implementation is called complete                                                                                                                |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Weight lifecycle / LYB-162                           | First supported agent data entry; successful create/read/correct/delete, zero duplicate writes/disclosure | Atomic receipt and rollback tests, revision/tombstone conflicts, kg/lb/date/DST fixtures, owned native/Siri reconciliation and persisted readback.                          |
| Client qualification / LYB-163                       | An agent becomes a customer's interface; supported journeys per client                                    | Separate OAuth, permissions, revoke/reconnect and real HTTP/MCP/native receipts for Claude Code, ChatGPT and Jovie; record a measured gap before CLI work.                  |
| Goals/preferences and deterministic summaries        | Extend goal/trend behavior; correct goal-relative answer with minimal input                               | Typed read/update/reset and deterministic summary contracts; units/dates/provenance, revision conflicts, safety and offline readback.                                       |
| Photo/import lifecycle / extend LYB-80               | Extend capture/import; owned confirmed imports without duplicates                                         | Device/source consent, preview/confirm, association, dedup, retry/correction/delete semantics, partial failures and persisted job/record readback.                          |
| Daily/GLP-1 records                                  | Extend daily logging; correct owned history with truthful boundaries                                      | Separate daily vs medication permissions and lifecycle contracts; preserve medical exclusion from this server and prove the native handoff outcome.                         |
| Export/deletion and integration status               | Extend account/integration controls; completed owned request without resurrection                         | Confirmation, subject isolation, in-flight/offline deletion safety, revoke/reconnect and export/delivery/provider readback; separate configuration, connection and history. |
| Training and voice / extend LYB-108, LYB-123, LYB-38 | Extend existing coaching actions; engine-authorized journey completion                                    | Preserve current ownership, branches and additive logging; explicit correction, durable retry/receipt and device voice boundaries, engine-only numbers and evidence IDs.    |

Retain Backlog/no-admission status and existing owners/branches. Do not dispatch,
claim locks, add release-blocking relations or gate the grandfathered beta.
No actual HTTP/MCP/native/provider acceptance or CI coverage is claimed by this
documentation-only plan; those receipts belong to the implementation slices.
