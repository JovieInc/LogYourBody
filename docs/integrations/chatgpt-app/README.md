# LogYourBody MCP server (ChatGPT, Grok, Muse)

One remote MCP server lets assistants read the user's LogYourBody hypertrophy plan and log
sets, including by voice. ChatGPT, Grok and any other MCP client call the same endpoint with
the same OAuth flow. Tracking issue: LYB-108 (epic LYB-107).

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

| Tool                    | Scope | readOnly | destructive | openWorld |
| ----------------------- | ----- | -------- | ----------- | --------- |
| `get_todays_workout`    | read  | true     | false       | false     |
| `log_sets`              | write | false    | false       | false     |
| `log_session_feedback`  | write | false    | false       | false     |
| `get_training_progress` | read  | true     | false       | false     |

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

Every number the tools return comes from the deterministic training engine or from the
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

Grok calls the same server; nothing in the server is ChatGPT-specific.

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
It must never use a shared service token to log on a user's behalf. Tracked in LYB-122.

## What stays out

GLP-1 data, body composition, photos and anything medical stay out of this server until a
reviewed decision says otherwise. OpenAI bans protected health information, limits
sensitive data to what the app strictly needs, and lists Ozempic under prohibited commerce.
