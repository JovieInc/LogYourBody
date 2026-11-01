# LYB-163 client qualification and CLI decision

Status: **Backlog; no client qualified**. Source review: November 1, 2026,
`JovieInc/LogYourBody` main `f980dc55288d4d65654107fc41c236283258f795`.
This is the qualification runbook for follow-up work under the
[canonical parity plan](README.md#client-qualification-and-focused-backlog-contracts),
not a receipt of client, issuer, device or provider execution. GBrain was
unreachable; findings below come from repository and linked upstream sources.

Decision: compose existing LYB product actions, HTTP/MCP transport and the
maintained official TypeScript client/Inspector CLI. **Do not build an LYB CLI
now.** No repeated scripting gap has been demonstrated. Client packages may
supply reviewed instructions, configuration and discovery only; never tokens,
business rules or broader authority. Keep records, actions and receipts portable
in versioned LYB schemas behind Platform ports/adapters.

This planning change authorizes no dependency installation, client registration,
account connection, domain exposure, dispatch/admission labels, publication or
release operation. Preserve existing owner/state/labels and LYB-108/120/121/122
branches. Current beta, held release PR and latest-main TestFlight remain
grandfathered with no new release dependency. The harness owns push/PR/merge.

## Qualification matrix

The supported first lifecycle is manual weight create/read/correct/delete from
[LYB-162](README.md#first-implementation-slice-manual-weight-lifecycle).
Training and vault capabilities retain their own gates, scopes and consent.
The [capability inventory](README.md#canonical-ios-capability-inventory) owns
remaining product gaps; an unavailable action must report unsupported or offer
a truthful handoff. Do not implement business logic separately for each client.

| Entry point                    | Authentication and connection to prove                                                                                                    | Reused action boundary                                                                                 | Missing acceptance                                                                                                                          |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Native iOS                     | Current app session and resolved owner; no delegated MCP grant inferred                                                                   | `BodyMetricLoggingService` and native editing/sync                                                     | Current build, owned record readback, offline reconciliation and actual device effects                                                      |
| Siri / App Intents / Shortcuts | App session, protected-data availability and device permissions; no delegated token                                                       | Existing `LogWeightIntent`, `LogBodyFatIntent`, `ShowLatestMetricsIntent` → `BodyMetricLoggingService` | Actual device invocation, clarification/cancel, repeat/retry/resume, local save/sync status; dedicated correction/delete intents are absent |
| Product HTTP                   | Per-user resource-bound bearer, metrics read/write scopes, explicit LYB grant                                                             | Existing `/api/metrics/weight` routes and shared lifecycle action                                      | Real issuer/environment, persistence and native reconciliation; local route tests alone do not qualify a client                             |
| Claude Code                    | Its own verified registration/redirect, PKCE S256, resource/scopes and explicit user LYB connection                                       | Existing remote MCP `tools/list` and `tools/call`                                                      | Exact client/version OAuth, lifecycle, isolation, reconnect/revoke and denial/readback receipts                                             |
| ChatGPT                        | Independently verified registration/redirect, PKCE S256, resource/scopes and explicit user LYB connection                                 | Same MCP actions; vault view/confirmed sharing stays separate                                          | Same lifecycle receipts plus hosted policy review; voice-mode tools need their own actual client test                                       |
| Jovie                          | Independently verified registration/redirect, per-user PKCE/resource/scopes and explicit LYB connection even with an existing Jovie `sub` | Same MCP actions through the Jovie adapter                                                             | Same lifecycle receipts plus session ownership, retention and connection-gate evidence; no fleet service token as a customer                |
| Official SDK / Inspector       | Synthetic harness first; later separately consented per-user OAuth, exact client registration and redirect                                | Same remote transport and actions                                                                      | Protocol baseline only; success cannot qualify Claude Code, ChatGPT, Jovie or Siri                                                          |
| Optional LYB CLI               | Only after the gap decision below; same delegated authority as HTTP/MCP                                                                   | Thin adapter to existing actions                                                                       | Not proposed or implemented; no CLI framework or runtime                                                                                    |

`agent/` is the external eve.dev core-chat backend, not Jovie's internally named
Eve product. Neither a Jovie identity nor an eve session grants LYB access.
Verify owner binding, account switching, session retention/deletion and each
connection gate independently. No shared service credential may impersonate a
customer. Source context: [core-chat migration](../../architecture/eve-core-chat-migration.md).

Keep separate status fields for each claimed client. `pending` means no accepted
receipt; it never means a provider rejection or an installed integration.

| Client           | Installation/config           | Registration + OAuth/connection | Read              | Create/correct/delete                                                         | Reconnect + revoke/denial                                                            | Hosted policy + disclosure                 | Publication                            |
| ---------------- | ----------------------------- | ------------------------------- | ----------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------ | -------------------------------------- |
| Claude Code      | pending                       | pending                         | pending           | pending                                                                       | pending                                                                              | pending                                    | not requested                          |
| ChatGPT          | pending                       | pending                         | pending           | pending                                                                       | pending                                                                              | pending                                    | not requested; LYB-120 owns submission |
| Jovie            | pending                       | pending                         | pending           | pending                                                                       | pending                                                                              | pending                                    | not requested                          |
| Siri / Shortcuts | source exists; device pending | app-session/device pending      | pending on device | weight source exists; body-fat contract and correction/delete intents pending | app sign-out/account-switch denial pending; delegated revoke also tested on HTTP/MCP | device/cloud processing disclosure pending | not requested                          |

Future results use `passed`, `failed`, `pending` or `unsupported` per case and
capability, with evidence links. Installation, identity, OAuth success, tool
discovery, product completion and marketplace publication are distinct outcomes.
Do not choose a winning client from an empty or partial receipt set.

## Cheap implementation order

1. Extend LYB-162's weight action/receipt fixtures first. Reuse the existing
   [weight route cases](../../../apps/web/src/app/api/metrics/weight/__tests__/route.node.test.ts)
   and [native logging boundary](../../../apps/ios/LogYourBody/Services/BodyMetricLoggingService.swift).
   Version a common fixture manifest before adapters consume it; name the LYB
   contract revision and source test/case per fixture. Keep synthetic values in
   isolated test memory and only opaque fixture IDs/assertions in receipt indexes.
2. Qualify thin adapters for existing weight/latest intents and HTTP/MCP with
   real device/client receipts, independently as each becomes available. Fix
   shared action gaps once at the product boundary.
3. Add body-fat and correction/delete intents only after their corresponding
   validation, identity, permission and receipt contracts pass. Weight authority
   does not grant body-fat or vault disclosure.
4. Revisit a thin CLI only with measured repeated scripting evidence below.

Do not build a universal voice runtime. Existing Swift source is not Siri or
AirPods runtime proof. Full-duplex Siri/AirPods remains a founder hypothesis,
not a verified Apple announcement or implementation dependency.

## Run protocol and acceptance cases

Start with synthetic subjects A and B, throwaway signing keys and isolated
storage. Only after that passes, use explicitly consented test accounts in a
named nonproduction environment behind default-off gates. Never use production
customer records as fixtures. Record gate evaluations, not just environment
variables: MCP and metrics flags plus `metrics_agent_weight_lifecycle` remain
closed without an affirmative evaluation. Training/vault gates are independent.
The README's October 4 issuer snapshot is historical; registration, redirects,
resource and scopes require fresh issuer evidence coordinated with JOV-7796.

For every delegated client, capture its public client ID and exact approved
redirect from registration, then show authorization-code PKCE S256, state/issuer
validation and `resource` on authorize/token requests. Verify access-token issuer,
audience and least required scopes without retaining token strings. A shared
`sub` or generic MCP login does not prove explicit LYB consent, entitlement or
connection. Check issuer denial for an unregistered redirect as well.

Use actual MCP `initialize`, `tools/list`, `tools/call` and returned results.
Match listed schemas/annotations and call `create_weight_entry`,
`list_weight_entries`, `correct_weight_entry`, `delete_weight_entry` only when
their gates permit. Preserve `result.isError`, errors and
`result.structuredContent` when assessing a response; HTTP 200 is not sufficient.
[Current contract](../../../apps/web/src/lib/mcp/contract.ts) supports
`2025-11-25`, `2025-06-18`, `2025-03-26`; record the negotiated version.
[Current handler](../../../apps/web/src/lib/mcp/handler.ts) advertises
`tools.listChanged=false`, with stateless JSON POST results and no SSE/domain-event
stream. Optional protocol notifications cannot mutate product state or prove
completion. Do not invent an “MCP events” standard.

Run the same versioned semantic cases across dialogs, UI and JSON. For app-session
entry points substitute real sign-out/account-switch/device denials for delegated
OAuth failures; still test delegated failures independently on HTTP/MCP.

| Case ID                    | Expected result and persisted proof                                                                                                                                                                                                                                          |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `weight.lifecycle`         | Resolve subject and measurement ID; create → read → correct the same ID with expected revision → read changed revision → delete → read tombstone and absence from live list. Verify owned persisted before/after state after each operation.                                 |
| `weight.value-time-source` | Explicit value/unit, kg/lb equivalence, measured instant, offset, local date, IANA zone/DST and provenance agree. Reject invalid/missing/ambiguous inputs without mutation; clarify instead of guessing.                                                                     |
| `weight.retry-repeat`      | Concurrent or lost-response retry with the same operation ID/payload returns the original receipt once; different payload conflicts. Intentional repeat has a new operation/measurement ID, even on the same day. Device reconstruction/resume must prove identity survives. |
| `weight.revision-delete`   | Stale revision fails unchanged, including concurrent correction/delete. Tombstone survives retries, offline sync and relaunch; no resurrection. Read persisted state after denial/conflict.                                                                                  |
| `auth.denials`             | Expired token, wrong audience, missing scope, missing LYB connection/consent, revoked consent and unavailable entitlement each deny without disclosure or mutation. Scope upgrade requires fresh consent; training permission never grants weight.                           |
| `auth.isolation`           | Subject B cannot list/read/correct/delete A's guessed record or replay A's operation. Account switch and in-flight session changes cannot return A's data to B. Read both subjects' persisted state after each attempt.                                                      |
| `auth.reconnect-revoke`    | Revoke with an otherwise unexpired token; next discovery/read/write attempts disclose no protected data or mutation. Reconnect requires explicit consent and cannot replay a queued write automatically. Verify new access, original IDs/revisions and no duplicate write.   |
| `gate.off`                 | With each required gate independently closed or unavailable, no protected tool/action access or mutation. The route gate returns 404 before auth; a hidden tool cannot be invoked by name. Check before/after data, not just UI visibility.                                  |
| `dialog.cancel`            | Cancel missing-unit/date/record clarification or destructive confirmation: no tool mutation and no saved row. A later explicit request has its own operation identity.                                                                                                       |
| `device.handoff`           | Denied/canceled/unavailable permissions, locked device, offline/save/sync failure and interrupted handoff remain truthful. Distinguish offered, pending, failed and completed. Correlate actual device outcome with the operation and app readback.                          |
| `device.reconcile`         | Local saved/pending cloud sync, cloud committed and conflict remain distinct. HTTP/MCP reports HealthKit `not_claimed`; only actual device evidence can prove a HealthKit effect. Dialog/UI/JSON must agree on state and freshness.                                          |
| `client.voice`             | Separate actual voice-mode invocation and persisted readback per client/version, including canceled clarification and a failed handoff. Text tools or source intent registration alone do not pass.                                                                          |

Acceptance requires all supported cases, zero cross-user disclosure, no duplicate
retry writes and truthful status. Report counts of supported/passed/failed/pending
cases per client/action. A failed isolation, consent, gate or completion claim
blocks qualification for that client; independent adapters can still progress.

## Redacted receipt contract

Extend the [existing completion evidence contract](../../USER_JOURNEYS.md#agent-parity-completion-evidence).
For each case retain:

- Receipt ID, fixture/contract version, UTC execution time, exact LYB code SHA,
  build/deployment ID, environment and real client/version/platform (OS/device
  build for intents); SDK/Inspector version and negotiated protocol if used.
- Resolved subject alias and ownership assertion, measurement ID, operation ID,
  prior/returned revision or tombstone identity, and request/result correlation.
- Registration/redirect reference, PKCE/resource verification, granted scopes,
  consent/connection/entitlement/revocation state and gate evaluation references.
  Record no tokens, auth codes, PKCE verifiers, headers or client secrets.
- Expected/observed status and assertions for value/unit/date/zone/provenance,
  plus protected persisted before/after evidence references and native/device
  reconciliation. Include failure and denial readback, not just successful calls.
- Redacted `tools/list` and `tools/call` result evidence, including errors and
  `structuredContent` assertions, CI/test run references and cleanup/deletion
  confirmation. Label simulated evidence as synthetic; never as a client pass.

Example index shape (placeholders only; not a passing receipt):

```json
{
  "schema": "lyb.client-qualification-receipt/v1",
  "status": "pending",
  "case_id": "weight.lifecycle",
  "fixture_version": "<LYB-162 fixture revision>",
  "code_sha": "<exact tested SHA>",
  "build": "<build/deployment ID>",
  "environment": "<isolated environment>",
  "client": { "name": "<client>", "version": "<actual version>" },
  "grant": { "subject_alias": "fixture-a", "scopes": [], "evidence_ref": null },
  "measurement_id": "<opaque test ID>",
  "operation_ids": [],
  "before_ref": null,
  "after_ref": null,
  "result_assertions_ref": null,
  "device_result_ref": null
}
```

General logs and repository receipt indexes/fixtures contain no health values,
tokens or raw transcripts. Detailed synthetic values stay in isolated fixtures;
consented-account evidence stays in access-controlled storage with named owner,
access policy, retention/deletion deadline and deletion proof. Redact before
export, including screenshots and tool results. A raw value hash is not adequate
redaction. Revoke is not proof that provider transcripts or local caches were
deleted; verify those separately.

## Adopt-first source audit and CLI gap

Audit date: November 1, 2026. Neither package is pinned in LYB's current lockfile;
the pins below are **evaluation candidates only**, not installed dependencies or
runtime compatibility receipts. Do not reuse October's unpinned SDK harness as
current-head acceptance.

| Candidate pin                                           | Source audit                                                                                                                                                                                                                                                                                                                                                  | Outstanding verification before use                                                                                                                                                                                |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `@modelcontextprotocol/client@2.4.0` (SDK tag `v2.4.0`) | [Manifest](https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/v2.4.0/packages/client/package.json): Node ≥20. [Catalog](https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/v2.4.0/pnpm-workspace.yaml): Zod `^4.2.0`. LYB Node 22.23.2/Zod 4.6.7 fit those declared ranges.                                             | Execute Streamable HTTP negotiation against LYB's supported versions, OAuth/refresh/resource behavior and structured results; verify resolved artifact integrity/dependency graph. No server SDK migration needed. |
| `@modelcontextprotocol/inspector@2.13.0` (tag `2.13.0`) | [Manifest](https://raw.githubusercontent.com/modelcontextprotocol/inspector/2.13.0/package.json): Node ≥22.19.0, SDK client/core 2.4.0, Zod `^4.4.3`; LYB pins fit. [CLI guide](https://raw.githubusercontent.com/modelcontextprotocol/inspector/2.13.0/docs/cli-smoke-testing.md) documents JSON results, stdout/stderr separation and stable exit statuses. | Execute discovery/call/error assertions with the pinned artifact. Validate storage, cleanup, network bindings and logging below. Never resolve `latest` for qualification receipts.                                |

The SDK [package manifest](https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/v2.4.0/packages/client/package.json)
declares Apache-2.0. Both pinned source LICENSE files describe an Apache-2.0/MIT
transition, with CC-BY-4.0 for nonspec documentation:
[SDK license](https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/v2.4.0/LICENSE),
[Inspector license](https://raw.githubusercontent.com/modelcontextprotocol/inspector/2.13.0/LICENSE).
Retain applicable license/copyright/attribution and any shipped NOTICE files;
review modified-file and copied-document attribution before redistribution.
Top-level NOTICE retrieval was unavailable for Inspector and 404 for SDK; this
does not certify absence from published packages. Tarball/transitive notices and
licenses remain pending until an authorized dependency-evaluation slice. Nothing
is vendored or redistributed by this plan.

Before real-account use, verify these settings on the pinned build:

- **Tokens:** Inspector [storage docs](https://raw.githubusercontent.com/modelcontextprotocol/inspector/2.13.0/docs/secret-storage.md)
  describe OS keychain selection and possible unencrypted file fallback. Use a
  verified OS keychain for reconnect tests, or fresh process-memory storage for
  disposable synthetic runs; refuse plaintext fallback for consented accounts.
  Credential headers can remain in config files: do not put bearer tokens there
  or in command arguments/history. Verify cleanup after revoke/account switch,
  including legacy state and backups. SDK OAuth storage belongs in a reviewed
  adapter using the same policy, never a product-domain token store.
- **Proxy exposure:** [network settings](https://raw.githubusercontent.com/modelcontextprotocol/inspector/2.13.0/docs/environment-variables.md)
  describe loopback binding and API authentication. Keep both, exact allowed
  origins and TLS verification; no auth-disable switches, all-interface bind,
  tunnels or public proxy. Inspect actual listeners/origins and outbound proxy
  configuration. CLI-only runs need no exposed web debugging UI.
- **Debug retention:** inspect actual stdout/stderr, filesystem logs, OAuth state,
  browser storage and crash uploads before accounts are connected. Disable raw
  payload/debug capture, redact credentials and health values at collection, keep
  only the receipt index in general logs. Name a retention owner/deadline and
  verify deletion of temporary state and protected evidence. Source defaults are
  not proof that a particular host stored nothing.

| Repeated workflow                                 | Existing tool to try first                                                             | Gap decision                                                                  |
| ------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Discover schemas and call an action from a script | Pinned Inspector CLI `tools/list`, `tools/call`, JSON output and documented exit codes | No demonstrated gap; do not build CLI                                         |
| Assert lifecycle, denial and readback over HTTP   | Official SDK client plus existing LYB action fixtures/tests                            | Needs execution receipts, not a second business layer                         |
| Login/reconnect/revoke safely                     | Maintained client OAuth plus verified local secret storage and issuer consent          | Provider/storage qualification pending; a custom CLI cannot substitute for it |
| Translate LYB results for a repeated automation   | Compose JSON assertions over existing receipts                                         | No repeatable failure or maintenance comparison supplied                      |

A future proposal must attach at least two concrete runs of the same scripting
task, pinned official-tool commands/results, the failed capability or excessive
manual work, and why configuration/composition or an upstream fix cannot close
it. Compare expected reuse and maintenance cost. Only then propose a thin
action adapter with JSON stdout, diagnostics on stderr and deterministic exit
codes for validation, auth/consent, conflicts, transport and unsupported/device
outcomes. It must retain operation/revision identities and the same gates and
per-user authority; no framework, daemon, new runtime or token bypass.

## Hosted-client policy and provider steps

Before domain exposure, each hosted client needs a dated, version/account-tier
specific review of its current official health/media rules, permitted payloads,
processing/subprocessors, training use, storage locations, retention, deletion
and revoke behavior, plus the disclosure users actually see. Record policy URLs,
review owner, decision and evidence; unresolved items stay pending. Claude Code's
model host also needs review even when the executable runs locally. ChatGPT's
vault consent does not approve manual weight disclosure or voice processing.
Jovie/eve session ownership, retention and connection gates need independent
evidence. This source review makes no provider-policy acceptance claim.

Installation/config review, client registration, user account connection,
marketplace submission/publication and owner attestation each need their own
status and receipt. Preserve LYB-108 server, LYB-120 ChatGPT submission, LYB-121
Grok and LYB-122 Muse ownership. This lane dispatches none of them. A plugin
listing or published package never grants access to an LYB customer account.
