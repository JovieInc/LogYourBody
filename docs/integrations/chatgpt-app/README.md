# LogYourBody MCP server (ChatGPT, Grok, Muse)

One remote MCP server lets assistants read the user's LogYourBody hypertrophy plan and log
sets, including by voice. ChatGPT, Grok and any other MCP client call the same endpoint with
the same OAuth flow. Tracking issue: LYB-108 (epic LYB-107).

## Product API and MCP parity (LYB-161)

Founder direction, October 13, 2026: an authorized agent may be the customer's
entire interface. Every iOS capability needs a product API + MCP action or an
explicit device/system/user handoff with completion readback. The
[roadmap specification requirements](../../product-development-roadmap.md#product-api-and-agent-parity--october-13-direction-lyb-161)
apply when a feature is new or materially extended.

This inventory is documentation-only backlog planning. It does not establish
runtime parity, connect accounts, install dependencies, dispatch work, add
admission labels/locks, publish a plugin, or gate the grandfathered TestFlight
beta/held release PR. Latest-main TestFlight delivery remains separate and higher
priority. Preserve existing ownership, branches, gates, and release controls.

### Canonical capability inventory

Original source anchor: main `bf05b7175bb3d8c8e8c6c24e29b11d301c70299e`.
Reconciled October 31 against main `94d019ba1c0507cfe122a183e0c8df621e160b1f`.
Paths below are source evidence, not deployed or client-qualified receipts.
“Gap” means a contract or execution proof is still required, not permission to
expose data. Update the relevant row and journey evidence in the same feature PR.

| iOS capability and source                                                                                                                                                                                                                                                                                                                      | Existing product API / MCP mapping                                                                                                                                                                                                          | Gap or required execution boundary                                                                                                                                                                                                             |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sign-in, profile, onboarding and consent: [AuthManager](../../../apps/ios/LogYourBody/Services/AuthManager.swift), [profile editing](../../../apps/ios/LogYourBody/Views/PreferencesView+AccountSection.swift)                                                                                                                                 | First-party `/api/auth/mobile/session` and `/api/auth/mobile/profile`; MCP resource-token validation                                                                                                                                        | Shared `sub` is not connection/consent. User performs Apple sign-in and safety enrollment. Specify delegated profile reads/edits and separate per-client grants/revocation.                                                                    |
| Manual weight create/read/correct/delete: [BodyMetricLoggingService](../../../apps/ios/LogYourBody/Services/BodyMetricLoggingService.swift), [App Intents](../../../apps/ios/LogYourBody/Services/BodyMetricAppIntents.swift)                                                                                                                  | `/api/metrics/weight`, `/corrections`, `/deletions` and `create_weight_entry`, `list_weight_entries`, `correct_weight_entry`, `delete_weight_entry` share [weight lifecycle actions](../../../apps/web/src/lib/metrics/weight-lifecycle.ts) | Source implemented behind gates (LYB-162); issuer, real clients, native reconciliation and device receipts remain independently unverified here. Cloud weight is not an Apple Health write.                                                    |
| Body fat/other composition, imported corrections, exclusion and undo: [logging](../../../apps/ios/LogYourBody/Services/BodyMetricLoggingService.swift), [MetricCorrectionService](../../../apps/ios/LogYourBody/Services/MetricCorrectionService.swift)                                                                                        | Native body-metric sync exists; `LogBodyFatIntent` saves locally. No general composition lifecycle tools                                                                                                                                    | Specify per-measurement action contracts and revisions before adding body-fat/correction/delete intents. Imported overlays must preserve original source and must not mutate HealthKit/provider records. Vault access is a separate boundary.  |
| Goals, dated outcomes, units and preferences: [goal editing](../../../apps/ios/LogYourBody/Views/PreferencesView+TrackingGoalsSection.swift), [DatedOutcomeStore](../../../apps/ios/LogYourBody/Services/DatedOutcomeStore.swift)                                                                                                              | Mobile profile and `/api/auth/mobile/dated-outcome`; no matching general MCP preference actions                                                                                                                                             | Separate device-local preferences from cloud goals; specify owned read/set/reset/correct actions, units, revisions and persisted readback. Do not infer personal targets.                                                                      |
| Latest metrics, history, deterministic trends and insights: [latest intent](../../../apps/ios/LogYourBody/Services/BodyMetricAppIntents.swift), [MetricsInterpolationService](../../../apps/ios/LogYourBody/Services/MetricsInterpolationService.swift)                                                                                        | Weight list/read exists; latest native summary is local. Training progress is a separate engine action                                                                                                                                      | Define deterministic domain reads with date ranges, provenance, freshness and estimate/reference/target distinctions. Agent prose cannot calculate replacement trends or prescriptions.                                                        |
| Photos, timeline browsing, attach/remove, comparison and share/export: [photo tools](../../../apps/ios/LogYourBody/Views/HomeV2/HomeV2PhotoToolsSheet.swift), [PhotoUploadManager](../../../apps/ios/LogYourBody/Services/PhotoUploadManager.swift), [BodyScoreShareExport](../../../apps/ios/LogYourBody/Services/BodyScoreShareExport.swift) | `/api/auth/mobile/photos`; gated vault view/confirmed-share tools are separate                                                                                                                                                              | Specify owned asset/measurement actions and attachment/removal semantics. Camera/library selection and share-sheet delivery require device/user handoffs. Do not return raw photos in general MCP results.                                     |
| Bulk photos, DEXA/PDF and BodySpec import: [BulkImportManager](../../../apps/ios/LogYourBody/Services/BulkImportManager.swift), [BodySpecDexaImporter](../../../apps/ios/LogYourBody/Services/BodySpecDexaImporter.swift), [DEXA sheet](../../../apps/ios/LogYourBody/Views/DexaPDFImportSheet.swift)                                          | Existing native import and first-party PDF parsing routes; no general import MCP action                                                                                                                                                     | Focused select/preview/confirm/import/status contracts need source identity, duplicate/retry rules, parse-failure receipts and partial completion. Local file/provider authentication is a handoff.                                            |
| Daily steps/activity and GLP-1 records: [DailyMetrics](../../../apps/ios/LogYourBody/Models/DailyMetrics.swift), [Glp1DoseLog](../../../apps/ios/LogYourBody/Models/Glp1DoseLog.swift)                                                                                                                                                         | Native record sync transports these collections; no corresponding MCP product actions                                                                                                                                                       | Generic table sync is not an agent action. Define daily-record lifecycle separately; GLP-1/medical content stays outside this server under current policy. Use an explicit native handoff unless a reviewed health-data decision permits more. |
| Engine-led training plans, sets, correction/undo, feedback and progress: [TrainingService](../../../apps/ios/LogYourBody/Services/TrainingService.swift)                                                                                                                                                                                       | Mobile `/api/auth/mobile/training/v1/*`; [training tools](../../../apps/web/src/lib/mcp/tools.ts) include workout, sets, control, correction, feedback, swap, progress and gated program revision                                           | Extend LYB-108/123/80; preserve additive `log_sets`, separate explicit correction and engine-only numeric prescriptions. Qualify each action and enrollment handoff; no general workout tracker.                                               |
| Core chat, voice input and spoken replies: [ChatService](../../../apps/ios/LogYourBody/Services/ChatService.swift), [VoiceCaptureService](../../../apps/ios/LogYourBody/Services/VoiceCaptureService.swift)                                                                                                                                    | First-party mobile chat/voice routes; bounded product tools are the mutation boundary                                                                                                                                                       | Microphone permission/capture and audio playback are device effects. Distinguish action selection from argument extraction; preserve conversation ownership, consent and existing voice gates (LYB-38).                                        |
| Integration status, connect/disconnect and sync: [IntegrationsView](../../../apps/ios/LogYourBody/Views/IntegrationsView.swift), [HealthSyncCoordinator](../../../apps/ios/LogYourBody/Services/HealthSyncCoordinator.swift), [BodySpecAuthManager](../../../apps/ios/LogYourBody/Services/BodySpecAuthManager.swift)                          | Existing native/provider adapters and sync APIs; no general integration-status MCP action                                                                                                                                                   | Specify status, freshness, pending/conflict and revoke/reconnect actions. HealthKit access stays device-owned; distinguish LYB grant, issuer token and provider connection. A request to sync is not completion.                               |
| Data export and account deletion: [ExportDataView](../../../apps/ios/LogYourBody/Views/ExportDataView.swift), [DeleteAccountView](../../../apps/ios/LogYourBody/Views/DeleteAccountView.swift)                                                                                                                                                 | `/api/auth/mobile/export` and `/api/auth/delete-account`; no equivalent delegated MCP action                                                                                                                                                | Define explicit confirmation, delegated scope, export delivery, retention/erasure boundaries and readback. Account deletion must invalidate agent access and prevent delayed native writes from restoring data.                                |
| Reminders/notifications and biometric lock: [NotificationManager](../../../apps/ios/LogYourBody/Services/NotificationManager.swift), [BiometricLockView](../../../apps/ios/LogYourBody/Views/BiometricLockView.swift)                                                                                                                          | Native settings and system adapters; no remote system-permission action                                                                                                                                                                     | Agent may request a device handoff. Permission, scheduling, delivery and biometric success are distinct; unavailable/denied/cancelled states cannot report completion.                                                                         |
| Subscription, purchase/restore and entitlement: [RevenueCatManager](../../../apps/ios/LogYourBody/Services/RevenueCatManager.swift), [subscription settings](../../../apps/ios/LogYourBody/Views/PreferencesView+SecuritySubscriptionSection.swift)                                                                                            | StoreKit/payment adapter and existing entitlement checks                                                                                                                                                                                    | User/system purchase or restore handoff; provider-confirmed entitlement readback. A shared identity, opened paywall or MCP token cannot confer paid access. No billing changes in this plan.                                                   |
| Account security, logout and signed-in devices: [AuthManager](../../../apps/ios/LogYourBody/Services/AuthManager.swift), [SecuritySessionsView](../../../apps/ios/LogYourBody/Views/SecuritySessionsView.swift)                                                                                                                                | Native session read/revoke and logout flows; no delegated session-management MCP action                                                                                                                                                     | Specify confirmed owned session revocation and provider readback. Local logout, issuer-session revocation and LYB agent-grant revocation are distinct effects.                                                                                 |
| Support, bug reports and legal documents: [BugReportViews](../../../apps/ios/LogYourBody/Views/BugReportViews.swift), [LegalDocumentView](../../../apps/ios/LogYourBody/Views/LegalDocumentView.swift)                                                                                                                                         | Existing native support/legal surfaces; no support-submission MCP action                                                                                                                                                                    | Link/read legal content or hand off to native support. Sending a report needs explicit user intent, attachment consent and delivery readback; opening a composer is not a sent report.                                                         |

Conversation send/read/history/retry/delete under the existing mobile chat API
also needs a delegated action or truthful native handoff; training tools do not
confer transcript access. Photo timeline comparison, timelapse and share/export
remain device actions until their owned-asset contracts and delivery receipts pass.

### Shared action and execution contract

Compose existing first-party routes, typed domain actions, platform ports and
adapters. Core Data remains the device/offline authority; native never connects to
Postgres. A server receipt proves only its committed cloud effect until native
reconciliation is observed. Apply ownership, entitlement and default-off gates at
the action boundary regardless of entry point. An agent cannot select another
subject, bypass consent, or use a fleet/service token as a customer.

Each focused contract records read/create/correct/delete/handoff mapping,
validation, units, timestamp/local date/zone/provenance, stable record and operation
IDs, transactionally stored result receipts, conflict revisions, tombstones, and
offline merge behavior. Identical retries reuse an operation ID and receipt;
intentional second entries get new IDs even when value/date match. Corrections
target an owned measurement and expected revision, never a replacement create.
Deletion must survive delayed native pushes. Preserve original imported values
and report conflicts instead of silently overwriting them.

Handoffs must name the required device/system/user action and provide a way to
read back the actual outcome. HealthKit, camera, library, microphone,
notifications, biometrics and StoreKit cannot be executed remotely just because
HTTP/MCP accepted a request. Report local saved, sync pending, cloud committed,
conflict, denied, cancelled, unavailable and device effect separately as relevant.
Never infer success from a dialog, navigation, empty HealthKit read, or accepted
job. Preserve health-data minimization and the vault's explicit confirmed-share
boundary; this inventory grants no broader health-data access.

### Entry-point-to-action mapping — October 13 clarification

Cheap maintained adapters provide optionality without choosing a universal
runtime or requiring a custom CLI. All entry points map to the same action levels:

| Entry point            | Read/create                                                                                         | Correct/delete/device handoff                                                 | Completion evidence                                                               |
| ---------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Native controls        | Reuse product services and Core Data                                                                | Owned ID/revision; system adapters for device effects                         | Local persistence, queued sync, cloud reconciliation and device effect separately |
| Siri / App Intents     | Reuse `LogWeightIntent`, `LogBodyFatIntent`, `ShowLatestMetricsIntent` → `BodyMetricLoggingService` | No correction/delete intents in current source; add only after contracts pass | Dialog/snippet must reflect actual local/pending/cloud/device state               |
| Product HTTP           | Typed product actions behind first-party routes                                                     | Same validation, owned ID/revision, tombstones; explicit device handoff       | Durable committed/replayed/conflict receipt plus persisted readback               |
| MCP                    | Thin tool adapters over the same actions                                                            | Same authorization and mutation semantics as HTTP                             | JSON tool result and persisted readback; no success inferred from tool discovery  |
| CLI, only if justified | Thin authenticated adapter to the same API/actions                                                  | Same IDs, revision, confirmation and handoff contract                         | Machine-readable result and readback; no independent store/runtime                |

At the original anchor the intents lacked explicit date/operation IDs. Current
`LogWeightIntent` retains generated record/operation IDs per intent instance; it
still has no measured-date parameter. A new instance does not establish durable
retry identity across a process restart. `LogBodyFatIntent` has no explicit date or
operation ID; correction/delete intents remain absent. Future adapters must
preserve authenticated subject, measurement identity, validation, units/date/zone,
provenance, revisions, retry IDs, permission boundaries and truthful receipts.
Local Siri success is not cloud completion or a qualified agent connection.

“MCP events” introduces no new LYB standard. The [handler](../../../apps/web/src/lib/mcp/handler.ts)
implements initialize/ping/tools/list/tools/call, advertises `tools.listChanged=false`,
and returns stateless JSON POST results; the [route](../../../apps/web/src/app/api/mcp/route-handlers.ts)
returns GET 405 with no SSE resume/domain-event subscription. Current source also
has gated vault resources/list/read, not a mutation event channel.
`structuredContent` is a result payload; protocol notifications are neither
mutation commands nor durable receipts. Future notifications need negotiated
supported capabilities and the same action/receipt identities.

Full-duplex Siri through AirPods is a founder hypothesis, not a verified Apple
announcement or available dependency. Mira Thud is a research candidate without
an available public API or verified weights dependency; it selects no new model
or runtime. Action selection and argument extraction remain distinct concerns.

### Client qualification and focused follow-ups

Adopt the official MCP client/Inspector for protocol conformance and dogfood.
Do not build a durable agent platform or require a new CLI. Qualify clients
independently; shared Jovie identity does not connect a customer to LYB.

| Client (LYB-163) | Required qualification                                                                                                  | Evidence in this planning change                                 |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Claude Code      | Per-user OAuth/resource audience, least-privilege consent, supported action calls, revoke/reconnect, persisted readback | Pending; no account connected or provider test performed         |
| ChatGPT          | Same checks using its own registered client and permitted data/widget boundary                                          | Pending; earlier local SDK tests do not prove real client access |
| Jovie            | Explicit LYB connection/consent and per-user scopes, supported calls, revoke/reconnect, persisted readback              | Pending; shared issuer identity is insufficient                  |

Each implementation receipt names commit/environment, client/version, supported
journey, scopes/grant and gate state, operation/record/revision, result and
independent persisted readback. Include wrong-user/permission denial, retry after
lost acknowledgement, revocation and reconnect. Redact tokens, account identifiers
and health content. Use actual HTTP/MCP/native/provider tests and exact-head CI
coverage; source inspection, fixtures and tool discovery alone are insufficient.
Provider registration, plugin/marketplace packaging and provider approval are
separate from protocol conformance and are not authorized here.

Work order and retained ownership:

1. LYB-162: weight action/receipt fixtures,
   delegated metrics scopes, atomic idempotency, revision/tombstone/native reconciliation
   and Siri mapping; extend the existing implementation rather than recreate it.
2. LYB-163: thin adapters for existing
   weight/latest intents and HTTP/MCP, on-device and independent client qualification.
   Independent adapters need not wait for every client. Add body-fat/correction/delete
   intents only after their corresponding contracts pass.
3. As existing features extend, split inventory gaps into focused contracts for
   goals/preferences, deterministic trends, photos/imports, daily records,
   export/deletion and integration status. A thin CLI requires a measured scripting
   gap and uses the same actions; no speculative required CLI.

Extend LYB-108, LYB-123, LYB-80 and LYB-38, preserving their owners, branches
and additive logging semantics. Coordinate resource audience, delegated scopes,
OAuth clients and consent with issuer owner
JOV-7796.
This plan makes no external issue/state/ownership changes and adds no release block.

## Surface

| Item                 | Value                                                                                                          |
| -------------------- | -------------------------------------------------------------------------------------------------------------- |
| Endpoint             | `POST https://www.logyourbody.com/api/mcp` (stateless Streamable HTTP, JSON responses)                         |
| Resource metadata    | `/.well-known/oauth-protected-resource/api/mcp` (RFC 9728), alias at `/.well-known/oauth-protected-resource`   |
| Authorization server | Jovie Better Auth issuer `https://jov.ie/api/auth`                                                             |
| Scopes               | `lyb:training.read`, `lyb:training.write`                                                                      |
| Flags                | `LYB_CHATGPT_MCP_ENABLED=true` and `LYB_HYPERTROPHY_COACH_API_ENABLED=true`; otherwise every route answers 404 |
| Code                 | `apps/web/src/lib/mcp/`, `apps/web/src/app/api/mcp/`                                                           |

Training tools in current source (all `openWorld: false`; `read`/`write` below
mean the corresponding `lyb:training.*` scope). Additional weight and vault tools
have their own scopes and gates described below.

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

`revise_training_program` is listed only when the delegated-programming gate is
enabled; proposal and apply/reject are distinct actions. Tool annotations above
reflect current source, not client qualification or durable retry guarantees.

`log_sets` only adds sets. It never overwrites a logged set and never logs beyond the
engine's plan, so `destructiveHint: false` is accurate. It previews the plan before
starting a session, so a misheard exercise name writes nothing. The shared set writer
atomically keeps the first saved value for a session/exercise/set identity. Identical
retries return that original record; different values return `set_conflict` (HTTP 409
on the mobile route). A correction uses the separate, explicit `correct_set` action.

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

- Developer mode: Settings, Apps, Developer mode, add `https://www.logyourbody.com/api/mcp`.
  ChatGPT reads the resource metadata, runs OAuth against the Jovie issuer, then lists tools.
- Voice: in ChatGPT voice mode the model calls the same tools. Inputs are shaped for
  speech: loose exercise names, `weightUnit: "lb"` converted to kilograms on the server,
  set numbers filled in automatically.
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
