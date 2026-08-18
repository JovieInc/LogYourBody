# LogYourBody core chat on eve.dev

This directory is the backend agent definition for LogYourBody's core chat on the external [eve.dev](https://eve.dev/) framework. It is separate from Jovie's internally named Eve agent/product. The native Swift/SwiftUI app remains a client of a first-party server API and does not embed the JavaScript framework.

## Scope

- `agent/instructions.md` defines the core health-chat, shared-identity, consent, and privacy contract.
- `agent/instructions/account-connection.ts` adds connection-state instructions from server-verified session attributes.
- `agent/agent.ts` selects the eve runtime model.
- `agent/channels/eve.ts` allows loopback development and fails closed for other callers until Jovie route authentication and per-session authorization are implemented.
- General shell, file, web, delegation, and planning tools are explicitly disabled. No health-data tool or external connection is present in this slice.

The agent cannot infer a LogYourBody connection from Jovie identity. A future first-party data adapter must provide a server-verified connection state, explicit scopes, and caller-scoped data. Until then, an unconnected caller receives connection guidance and no health data is read.

## Local validation

Run the credential-free smoke eval from the repository root:

```bash
corepack pnpm --config.engine-strict=false eve:smoke
```

The command uses pinned Node 24.12.0 for eve 0.27.13, boots only a loopback runtime, and verifies deterministic connected and unconnected account states without a provider credential. It removes eve's generated local runtime and workflow state before and after the run so stale fixtures cannot affect the result or repository guards. It does not create a project, external connection, schedule, or deployment.

The web workspace remains on Node 20.x. Do not change that application engine
contract to satisfy eve's Node 24 runtime requirement. `eve:dev` needs a model
credential and remains a local, interactive command; never add that credential
to the repository.
