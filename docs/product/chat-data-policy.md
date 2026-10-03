# Authenticated chat data policy

LogYourBody chat is a first-party, authenticated product surface. The mobile
app sends its existing Jovie OAuth bearer token to the LogYourBody server. The
server validates the token before it reads profile data, body metrics, or a
conversation.

## Data used for an answer

- The user's message and up to 20 recent conversation messages.
- A minimized profile projection: height and explicit goal weight only.
- Up to 30 recent body-metric rows: date, weight, body-fat percentage, muscle
  mass, and unit.

Names, email addresses, profile photos, metric notes, photo URLs, and source
metadata are excluded from model context. The selected context is sent to the
configured server-side model provider only to generate the requested answer.
It is not copied into chat-message storage, embedded, vectorized, or sent to an
external indexing system.

The production chat and PDF adapters use OpenAI's Chat Completions API. [OpenAI documents](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint)
that API inputs and outputs are not used for model training by default, while
abuse-monitoring logs may retain customer content for up to 30 days unless the
project has approved Zero Data Retention. Those calls send `store: false`, which
turns off application-state storage (dashboard logs and distillation). The OpenAI
SDK cannot grant the abuse-monitoring exemption; that remains a project approval.
The OpenAI client logger is off so `OPENAI_LOG` cannot print prompts or completions.
Release owners must verify the active project-level data control before promotion;
LogYourBody does not claim a shorter provider retention window without that receipt.

## Provider zero retention

Direct Chat Completions calls (mobile chat and PDF extraction) always send
`store: false`. Options that can fail the request stay behind
`LYB_AI_ZERO_RETENTION=1`, which defaults off:

| Call                            | SDK control                                           | When the flag is off                                                             |
| ------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------- |
| ElevenLabs speech               | `enableLogging: false` (Zero Retention Mode)          | omitted; a non-enterprise account can reject the request                         |
| Fish Audio via AI Gateway       | `providerOptions.gateway.zeroDataRetention: true`     | omitted; an ineligible plan or model fails the request                           |
| eve model `openai/gpt-5.4-mini` | gateway `zeroDataRetention` and OpenAI `store: false` | omitted on the production model; local smoke and knowledge evals never send them |

These controls cannot be set from this code:

- OpenAI abuse-monitoring Zero Data Retention. `store: false` is not that approval.
- ElevenLabs batch speech-to-text (`scribe_v2` through `experimental_transcribe`). `@ai-sdk/elevenlabs` exposes `enableLogging` for speech synthesis and realtime transcription, not for this batch route.
- Fish Audio's own retention, apart from the gateway routing flag above. There is no direct Fish Audio client.
- eve durable run retention. eve 0.27 agent config can forward `modelOptions` only; it has no run-retention field. Jovie is the auth issuer here, not a model provider.

## Ownership and retention

Every conversation, turn, message, and rate-limit mutation is scoped by the
immutable authenticated user subject. Conversation history is retained for 30
days after its most recent activity. Expired conversations are inaccessible to
the chat API, purged opportunistically on every chat request, and removed by a
daily authenticated cleanup job. Deleting the current conversation removes its
turns and messages. Account deletion removes all conversations and rate-limit
counters before the product identity record is removed. Inactive rate-limit
counters are also purged after 30 days.

## Operational safeguards

- Model credentials remain server-only.
- Messages and body context are not written to application logs.
- A turn is idempotent by conversation ID and client-message ID.
- Valid send attempts pass persistent per-subject admission limits before any
  conversation row or model work is created. Context is bounded and model
  output is capped.
- Client cancellation aborts the provider request and marks the turn cancelled.
- Provider failures remain retryable with the same client-message ID.
