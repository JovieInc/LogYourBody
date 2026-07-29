# LYB eve agent scaffold

This directory is LYB's first [Vercel eve](https://vercel.com/docs/eve) agent. It is intentionally a local, private dogfood scaffold for Tim and product discovery only.

## Scope

- `agent/instructions.md` contains LYB context, the launch-critical journey, and privacy / no-side-effect rules.
- `agent/skills/private-dogfood-research.md` defines the private research procedure and sanitized output format.
- `agent/agent.ts` selects the eve runtime model.
- There are no tools, channels, connections, schedules, sandbox overrides, credentials, or external integrations.

The agent must not receive raw health exports or photos, and no raw gym conversation should be copied into repository artifacts. This scaffold does not create product work or send messages.

## Local validation

The repo's current Node runtime is older than eve's documented Node 24 requirement. On a Node 24+ environment with a model credential, run:

```bash
pnpm eve:info
pnpm eve:build
pnpm eve:dev
```

`eve:dev` is intentionally not run by CI or this PR; it requires a model credential and starts an interactive local runtime. No Vercel project is created by these commands.
