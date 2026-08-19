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

The repo's current Node runtime is **20.x**. Vercel Eve's documented CLI
requirement is **Node 24+**. Keep `package.json` `engines.node` on 20.x for
the web app and CI. On a Node 24+ environment with a model credential, run:

```bash
pnpm eve:info
pnpm eve:build
pnpm eve:dev
```

If the shell is still Node 20, an ephemeral Node 24 runner is enough, for
example `pnpm dlx node@24 node_modules/eve/bin/eve.js info`. Do not change
the app engine contract to make those commands the default.

`eve:dev` is intentionally not run by CI. It requires a model credential and
starts an interactive local runtime. No Vercel project is created by these
commands. Do not add secrets to the repo.
