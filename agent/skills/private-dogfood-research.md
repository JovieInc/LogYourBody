# Private dogfood research

Use this skill only for Tim's private LYB gym dogfood and product-discovery conversations. It is a procedure for observing and sanitizing experience, not a shipping workflow.

## Procedure

1. **Stay private.** Keep the raw conversation in the current private session. Do not copy raw health, gym, photo, location, schedule, or identifying details into files, tickets, commits, PRs, analytics, or external services.
2. **Extract the smallest useful signal.** Reduce the conversation to the minimum context needed to understand the friction or success. Remove exact measurements, dates, locations, names, photos, and other identifying details. If sanitization would make the signal unreliable, say that the signal is unavailable rather than retaining the raw detail.
3. **Classify evidence.** Every statement in the output must be labelled exactly once:
   - **Observed:** directly reported or directly seen in the dogfood session.
   - **Inferred:** a reasoned interpretation of an observation; state the reasoning briefly.
   - **Hypothesis:** a testable possibility, not a product requirement or truth.
4. **Anchor the journey.** Map the signal to one launch-critical journey step: check intent, open/understand, capture/confirm, answer “How am I doing?”, or leave/return. Note the affected dimension: trust, comprehension, effort, correctness, or repeat use.
5. **Propose the cheapest test.** Prefer a reversible, low-risk test such as a wording change in a private prototype, a scripted replay, a manual comparison, or a short follow-up dogfood session. Include what result would support or weaken the hypothesis. Never propose a production experiment or external outreach by default.
6. **Keep discovery separate from shipping.** A useful output can be handed to a human for review, but it must not create a GitHub issue, Linear issue, PR task, code patch, feature flag, release, or deployment. If asked to ship, provide a separate sanitized handoff draft and state that explicit human approval is required.

## Response format

```text
Private dogfood note

Sanitized observation
- [observed] ...

Interpretation
- [inferred] ...

Hypothesis
- [hypothesis] ...

Journey / risk
- Step: ...
- Dimension: ...

Cheapest next test
- ...
- Supporting result: ...
- Weakening result: ...

Boundary
- Discovery only; no product work was created and no external message was sent.
```

If there is no reliable signal, return `No sanitized observation available` and explain why without quoting the raw conversation. If the user asks for medical guidance, refuse that part and suggest a qualified professional; do not turn it into product evidence.
