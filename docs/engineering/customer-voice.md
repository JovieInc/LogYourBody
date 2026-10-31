# LogYourBody customer voice (2026-10-31)

Customer support ingress persists a minimal Neon ledger before handing each item
to Summer. Summer owns drafting and Tim's iMessage approval. LYB never initiates a
customer reply from capture. This branch is local implementation only; it does
not deploy, configure Cloudflare routing, install secrets, or prove an iMessage
was received.

## Privacy boundary

Arbitrary health-app messages cannot be made safe with keyword redaction.
`privateSupportSummary` reduces messages to fixed support-category sentences.
The Email Worker does this before its HTTP request; capture applies the same
boundary again. Neither message bodies, subjects, names, attachments, measurements,
health history, account profiles nor chat context are stored in this ledger or
sent to Summer. Unknown or large-message content produces a generic notice rather
than being dropped. This deliberately sacrifices verbatim detail: Tim can consult
the existing private support mailbox; Summer can draft an acknowledgement from the
categories but cannot reconstruct the original request. No request bodies, headers,
addresses, tokens or caught errors are logged by these paths. Keep Worker and
Vercel request-body logging disabled.

The only persisted contact data is `reply_to` and SHA-256(lowercased email +
`CUSTOMER_VOICE_SALT`). There is no established field-encryption adapter or
transactional email transport in the current web code. `reply_to` is therefore
stored as plaintext within the existing Neon database access boundary, as allowed
by the task; it is never included in the Summer event. Limit database access and
purge support rows when no longer needed. Sender hashes are pseudonymous, not
anonymous. No new client-accessible reads or native sync collections are added.

The unchanged original-message forward to the existing verified `FORWARD_TO`
mailbox is explicitly retained. This is the existing mail-delivery path, distinct
from Summer's privacy-limited event. No additional mailbox recipients are added.

## Adoption decision

Compose the existing Neon port/adapter pattern, the existing Cloudflare Email
Routing destination, and Jovie's production Summer OIDC/approval contract.
Cloudflare's [Email Worker API](https://developers.cloudflare.com/email-service/api/route-emails/email-handler/)
recommends [postal-mime](https://github.com/postalsys/postal-mime) for MIME parsing.
Its MIT-0-licensed parser runs in the Worker without credentials or network calls;
attachments are never forwarded to the new API. Use maintained MIT-licensed
[jose](https://github.com/panva/jose) for signed JWT/JWKS verification instead of
writing another verifier. Both versions are locked by pnpm. The product-specific
layer is the privacy summary, ledger and approval gate. Revisit if Summer changes
its versioned envelope/receipt or LYB adopts a transactional email port.

## Configuration and deployment

Web server environment (never `NEXT_PUBLIC_*`):

| Variable                        | Purpose                                                                                                                                                                              |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `DATABASE_URL`                  | Existing Neon runtime connection; migrations use the existing direct connection workflow.                                                                                            |
| `CUSTOMER_VOICE_SALT`           | Stable secret for sender hashes; required before capture.                                                                                                                            |
| `CUSTOMER_VOICE_INBOUND_SECRET` | Shared HMAC secret with the Email Worker.                                                                                                                                            |
| `SUMMER_BASE_URL`               | Trusted HTTPS origin only, e.g. `https://summer.jov.ie`; no credentials, path, query or fragment.                                                                                    |
| `VERCEL_OIDC_TOKEN`             | Deployment-provided token used as Bearer and `x-vercel-trusted-oidc-idp-token` for Summer. Enable Vercel OIDC for this deployment and authorize LYB's production identity at Summer. |

Worker configuration in `workers/customer-voice-email/wrangler.toml`:

- Set `INBOUND_URL` to the production inbound route.
- Set `FORWARD_TO` to the **existing verified** Email Routing destination.
- Supply `CUSTOMER_VOICE_INBOUND_SECRET` via Wrangler secret input; never a file.
- Install with the root pnpm workspace. Bundle/deploy with Wrangler from the Worker
  directory; route both `support@logyourbody.com` and `privacy@logyourbody.com` to it.
- Observability is disabled in the template. The Worker always attempts capture
  and existing forwarding independently. It retries failed HTTP capture three
  times using the identical signed body and then raises a fixed error; an operator
  must recover failed delivery from the existing mailbox. There is no new queue.
- Parsing is bounded to 1 MiB raw emails. Oversized or unparseable mail still
  produces a generic support event and is forwarded to the existing destination.

The app uses Next.js App Router under `apps/web/src/app`. Native/server callers
normally use first-party Bearer credentials validated by Jovie Auth; the existing
retention cron uses `CRON_SECRET`. Customer voice instead uses per-route HMAC
inbound and Summer production OIDC for replies, with no browser session bypass.
Jovie's reference OIDC issuer/audience/subject and project id are pinned in the
Summer adapter. Verify any future identity change against that service's owner.

The existing `.github/workflows/deploy.yml` deploys merged web changes: applies
`apps/web/db/migrations` through `db:apply:neon`, builds Vercel prebuilt output,
deploys production and smokes the deployed app. `vercel.json` disables automatic
Git deployment of `main`. Do not apply this migration or change provider settings
from the local implementation task.

## Inbound contract and recovery

`POST /api/customer-voice/inbound` takes a strict JSON body:

```json
{
  "id": "11111111-2222-4333-8444-555555555555",
  "receivedAt": "2026-10-31T00:00:00.000Z",
  "from": "original@example.org",
  "text": "Customer message received. Details withheld for health privacy.",
  "automated": false
}
```

`subject` (at most 200 characters) is accepted for first-party classification but
never stored/handed off; the Worker omits it. Signature header:
`x-customer-voice-signature: sha256=<hex HMAC-SHA256(secret, exact raw body)>`.
Bodies over 256 KiB are rejected while streaming, before JSON parsing. Stable
opaque IDs derived with HMAC from envelope sender/recipient/Message-ID deduplicate
provider redeliveries. Without Message-ID only retries within one invocation
share an ID. Reply destinations always use the original envelope sender; a
message's Reply-To header cannot override it. Automated mail is captured but is
nonreplyable. `/^browse-ready\+.*@jov\.ie$/i` senders set `test: true`.

Summer receives only the strict `company.customer-voice/v1` envelope with
`app: logyourbody`. It must deduplicate by app/id and return Jovie-compatible
`{result:{status:'pinged',pingedAt:<ISO>}}`, `digested` or `replay` receipts.
HTTP success alone is not accepted. Missing configuration or failed handoff sets
`stages['handoff-unavailable']` after persistence; the inbound response remains
202 once the ledger is durable. Query pending rows via the existing privileged DB
operations path with `where not (stages ? 'forwarded')`. Replaying the same signed
event reuses the saved row and retries pending handoff; already forwarded rows do
not ping again. The first timestamp for each stage wins. No background retry
scheduler or Summer stage callback is invented. `pinged` is recorded only from an
explicit Summer receipt; an absent ping timestamp remains unverified.

## Approval and unavailable reply transport

`POST /api/internal/customer-voice/[id]/reply` accepts only the Summer production
OIDC identity and Jovie's strict approval payload: `text` (byte-preserved),
`draftSha256`, `approvedAt`, and `approvalKey` (Summer's Photon admission key).
Summer is responsible for verifying Tim's actual approving message. This API
requires its receipt and exact text hash; it does not independently verify Photon.
Recipient/CC/BCC/Reply-To fields are rejected. The only destination is the original
row's `reply_to`. An atomic claim persists the approval receipt (without reply
text) before any transport call. Ambiguous send failures retain the claim to
prevent duplicate delivery and require provider reconciliation.

**No email transport is configured or simulated.** Valid, replyable approvals
currently return HTTP 501 `{ "code": "no-email-transport" }`; they do not record
approved/sent stages. Enabling real replies requires adopting the app's eventual
transactional-email port, wiring its idempotent adapter, and opening the
default-off Statsig gate `lyb_customer_voice_replies`. Until that work is completed,
Tim can approve drafts in Summer but this app cannot deliver them. No automatic
reply, fake success, or fallback sender exists.

## Coach chat insertion point

`agent/agent.ts` and `agent/channels/eve.ts` have no feedback-shaped user-turn
hook. `agent/tools/record_feedback.ts` is engine recovery feedback (soreness,
pump, performance, joint pain), **not customer support**; it must never feed this
loop. No agent or native chat transcript is copied here.

When the external eve.dev channel gains a server-verified user-turn lifecycle
hook, call `isFeedbackTurn` on the current user turn only, then invoke
`createCustomerVoiceCapture` with channel `chat`, a stable message UUID, time and
an authenticated account email if available. Apply the same fixed-summary privacy
boundary before crossing from agent to web; do not transmit transcript/context or
health fields. The existing first-party fallback is
`apps/web/src/app/api/auth/mobile/chat/v1/route-handlers.ts` immediately after
validated-message admission, but it currently has no support callback either.
This branch documents the hook rather than adding a second runtime integration.

## Verification

The root `pnpm lint --filter=logyourbody`, `pnpm typecheck --filter=logyourbody`
and `pnpm test --filter=logyourbody` run the repository's normal web checks.
Jest includes meaningful capture, inbound, reply, Neon and handoff tests with
coverage; the same existing web test/test:ci scripts additionally execute real
RS256 verification and real MIME Worker tests through tsx. No live health data,
external sends, provider credentials or deployed database are used in tests.

Local verification receipt (2026-10-31): web lint/typecheck, web `test:ci`
(169 Jest suites, 1,658 tests, plus seven Node runtime tests), `product:check`,
Neon migration layout, vendor boundaries, Next production build and Wrangler
`deploy --dry-run` passed. Capture, inbound authentication, reply logic and the
Summer adapter have 100% Jest line coverage. The default parallel root test run
also executed the full suite but twice exceeded the existing five-second timeout
in `MesocycleCanvasBoard.test.tsx`; that case passes in the unchanged sequential
`test:ci` runner. No timeout, coverage threshold or test selector was relaxed.
