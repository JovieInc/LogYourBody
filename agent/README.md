# LYB Vercel Eve agent scaffold

This directory is LogYourBody's first [Vercel Eve](https://vercel.com/docs/eve)
agent. It is a local, Tim-only gym dogfood and product-discovery companion.

**This is Vercel Eve, not the Summer / Jovie internal Eve persona.** In LYB
docs and issues, always write **Vercel Eve**. The gym loop and the
conversation → issue gate live in
[docs/product/vercel-eve-gym-dogfood.md](../docs/product/vercel-eve-gym-dogfood.md).

## Scope

- `agent/instructions.md` is the always-on LYB context, launch-critical
  journey, and privacy / no-side-effect rules.
- `agent/skills/private-dogfood-research.md` is the private research procedure
  and sanitized output format.
- `agent/agent.ts` selects the Vercel Eve runtime model through `defineAgent`.
- There are no tools, channels, connections, schedules, sandbox overrides,
  credentials, or external integrations. Do not add those slots.

The agent must not receive raw health exports or photos. No raw gym
conversation belongs in repository artifacts. This scaffold does not create
product work or send messages.

## Gym loop (short)

1. Open LYB on the personal device and use the product.
2. Later, capture a sanitized observation with the local Vercel Eve agent.
3. A human reviews the private note.
4. Only then may that human file a sanitized GitHub issue. The agent never
   files it.

## Local validation

Run the credential-free smoke eval from the repository root:

```bash
corepack pnpm --config.engine-strict=false eve:smoke
```

The command uses pinned Node 24.12.0 for eve 0.27.13, boots only a local runtime, and verifies deterministic two-turn session continuity without a provider credential. It removes Eve's generated local runtime and workflow state before and after the run so stale fixtures cannot affect the result or repository guards. It does not create a Vercel project, external connection, channel, schedule, or deployment.

The web workspace remains on Node 20.x. Do not change that application engine
contract to satisfy Eve's Node 24 runtime requirement. `eve:dev` needs a model
credential and remains a local, interactive command; never add that credential
to the repository.
