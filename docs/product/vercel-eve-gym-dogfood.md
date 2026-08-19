# Vercel Eve gym dogfood path

This is the Tim-only product-discovery loop for LogYourBody. It uses **Vercel Eve**,
the open-source agent framework documented at
[vercel.com/docs/eve](https://vercel.com/docs/eve).

It is **not** the Summer / Jovie internal Eve persona. Do not call this path
"Eve" in LYB issues, PRs, or docs. Use **Vercel Eve**.

The bounded scaffold lives in [`agent/`](../../agent/README.md). Related
Jovie-scoped Eve-pilot work stays in Jovie. This path does not authorize
production mutations, tools, channels, or a Vercel project.

This GitHub repository is public. Treat every issue, PR, and commit as public.

## What Tim does at the gym

1. **Open LYB on the personal iPhone.** Use a signed-in TestFlight or local
   build. If sign-in or the paid surface is broken, stop and fix that first.
   There is no useful dogfood signal from a blocked launch.
2. **Use the product as a user, not as a developer.** Before or after the
   session, check progress, capture or confirm a body metric, photo, or
   HealthKit-backed signal, and try to answer “How am I doing?”
3. **Do not file tickets from the gym floor.** Keep raw weights, photos, gym
   name, time, location, and conversation on the device or in your head.
4. **Later, on a private machine, talk to the local Vercel Eve agent.** Do not
   paste exports, photos, exact measurements, or identifying gym details.
5. **Read the private dogfood note.** The agent may only produce a sanitized
   observation, an inference, a hypothesis, and a cheap test. That note stays
   in the local session.
6. **Human review is the only gate to GitHub.** If the note is product-useful
   _and_ fully sanitized, Tim may copy a sanitized issue draft into GitHub by
   hand. If sanitization would drop the signal, keep it private.

## Conversation → issue feedback loop

```text
Use LYB on device (private)
        ↓
Local Vercel Eve session (`pnpm eve:dev` on Node 24+) (private)
        ↓
Sanitized dogfood note (still private)
        ↓
Human review (required)
        ↓
Optional sanitized GitHub issue, filed by a human (public)
        ↓
Normal LYB branch / PR / CI path
```

Rules:

- The Vercel Eve agent must not create GitHub issues, Linear issues, PRs, Slack
  or Telegram messages, analytics events, or any other external artifact.
- Raw gym, body, health, photo, location, schedule, and conversation detail
  must not leave the private session automatically.
- A handoff draft is allowed only when asked, and only after names, exact
  measurements, dates, locations, photos, and other identifying or
  health-sensitive content have been removed.
- Label every claim **observed**, **inferred**, or **hypothesis**. Discovery is
  not a ship decision.
- Prefer the cheapest reversible test. Do not propose a production experiment
  or customer outreach by default.

## Naming

| Name                                      | Meaning in this repo                                         |
| ----------------------------------------- | ------------------------------------------------------------ |
| **Vercel Eve**                            | The Vercel `eve` framework and this local `agent/` scaffold. |
| `pnpm eve:info` / `eve:build` / `eve:dev` | Local CLI wrappers. They do not create a Vercel project.     |
| Internal Eve, Summer Eve, Jovie Eve       | A different internal persona. Out of scope here.             |

## Runtime honesty

The repo engine is **Node 20** for the web app and CI. Vercel Eve's CLI
requires **Node 24+**. Do not bump `package.json` `engines.node` for this
path. Run the local CLI with a Node 24+ shell when needed. CI must not run
`eve:dev`.
