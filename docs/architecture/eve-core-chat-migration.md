# eve.dev core chat migration

## Decision

Adopt the external [eve.dev](https://eve.dev/) framework as the durable backend harness for LogYourBody core chat. LogYourBody remains a native Swift/SwiftUI product and does not embed the TypeScript runtime. The first-party mobile chat API remains the client contract while the server-side harness changes behind it.

The external framework is always styled `eve` and identified by its eve.dev origin. It is distinct from any internally named Jovie agent or product.

## Verified boundaries

```text
SwiftUI Chat -> LogYourBody first-party API -> eve runtime -> authorized product ports
                    |                         |
                    | Jovie bearer auth       | durable session and model loop
                    | conversation ownership  | no implicit product-data access
                    v                         v
              Jovie identity subject    scoped LogYourBody connection
```

- **Identity:** Jovie Better Auth supplies the stable person-level subject. Identity alone never means that a LogYourBody account is connected.
- **Connection:** a server-owned connection record must bind the Jovie subject to the LogYourBody product projection. The runtime receives only a verified connection state and explicit scopes.
- **Authorization:** health-data reads require both a current authenticated Jovie principal and a current LogYourBody connection with the required scope. A message cannot establish either fact.
- **Privacy:** profile, metrics, HealthKit-derived data, and photos stay behind first-party ports. They are minimized before model use and never placed in route-auth attributes, URLs, logs, or repository fixtures.
- **Unconnected state:** the agent explains that LogYourBody must be connected and returns a first-party connection handoff. It must not imply access or manufacture a session.
- **Session ownership:** eve route authentication does not itself enforce per-user ownership of durable sessions. The production cutover is blocked until the adapter binds every create, continue, stream, and cancel operation to the same verified Jovie subject.

## First implementation slice

This slice turns the repository's agent definition into the core-chat contract, adds dynamic connected/unconnected instructions, explicitly disables general-purpose shell/file/web/delegation tools, and authors an eve channel that fails closed by default. Loopback authentication requires an explicit non-production opt-in. Credential-free eve evals exercise both account states and durable two-turn continuity.

No health-data tool, production route authentication, account-connection mutation, deployment, or mobile protocol change is included. The existing first-party chat route and model adapter remain active.

## Cutover and rollback

The replacement boundary is the server-side implementation behind the existing mobile chat protocol. A later gated adapter can translate that protocol to eve session creation, continuation, streaming, and cancellation after these gates are proven:

1. Jovie token verification and LogYourBody connection lookup are server-side and fail closed.
2. Durable eve sessions are owned by the authenticated Jovie subject across create, continue, stream, and cancel.
3. Revocation removes health-data capability on the next turn and does not reuse prior context as current authorization.
4. Authorized tools use first-party product ports, least-privilege scopes, bounded output, and no raw credentials.
5. Existing idempotency, retention, deletion, rate-limit, and cancellation tests pass through the eve-backed adapter.
6. Provider data processing, retention, telemetry, sandbox egress, and deletion controls have release receipts appropriate for health data.

Until those gates pass, rollback is one boundary: keep the current `ChatModelPort` adapter selected and leave the eve channel unavailable to production callers. No iOS rollback is required because the mobile API contract does not change in this slice.

## Adopt-first receipt

- **Choice:** adopt eve.dev rather than build a new durable harness.
- **Fit:** filesystem-authored agents, durable sessions, reconnectable streaming, custom route auth, evals, and typed tools match the backend need.
- **Constraints:** eve 0.27.13 is preview software and requires Node 24, while the current web workspace declares Node 20. Production runtime packaging must therefore be isolated from the mobile client and must not silently change the web runtime.
- **Security boundary:** eve keeps runtime secrets outside its sandbox, but built-in capabilities and network policy are deployer responsibilities. This slice removes general-purpose capabilities and exposes no product-data tool.
- **Portability:** the native app continues to depend on the first-party chat protocol and internal product ports, not on eve's client types. The server adapter is the replaceable boundary.
- **Revisit trigger:** reconsider the adoption if session ownership cannot be enforced for every route, health-data retention/deletion cannot be proven, or the preview runtime cannot meet the product's availability and Node support requirements.
