# Backward planner (LYB-269)

`BackwardPlanner.plan(outcome:history:now:)` is a pure weight-planning function.
`Outcome` is a value projection until the persisted-outcome slice supplies its
model. It holds an explicit baseline date/weight and target date/weight. History
contains comparable weight measurements in kilograms. There is no UI, persistence,
network access, implicit clock, or nutrition/training prescription.

The required weekly change is `(target - baseline) / elapsed weeks to deadline`.
The planner keeps that original trajectory when new measurements arrive. It
compares the latest usable measurement with the expected weight **at that
measurement's timestamp**, and returns that timestamp as `evaluatedAt`. It does
not invent progress between the last measurement and `now`. Positive drift means
behind and negative means ahead, in either direction. Maintenance returns zero
weekly change and measured-minus-target drift. An expired deadline returns no
weekly rate and asks to review the outcome; it never extends the date.

Each result contains one action: hold, review progress, review outcome, or record
a measurement. Being ahead holds the plan. Missing/invalid history asks for a
measurement; conflicting weights at the latest timestamp ask for a new reading.
Invalid outcomes return a defined review result.

The caller must inject the engine's approved, signed kg/week bounds (including
zero). Neither this repository's current engine nor the Jovie v1 fixture supplies
approved weight loss/gain bounds. The planner therefore has **no numeric defaults**.
Missing/non-finite bounds fail closed to review. Both the original requirement
and the remaining requirement at the latest measurement must fit the supplied
bounds; unsafe dates return review, without clamping the requirement. Production
integration must supply reviewed bounds and apply the parent journey's freshness,
provenance, safety eligibility, and feature-gate checks before presenting a plan.

The test resource `LogYourBodyTests/Fixtures/lyb-launch-contract.json` is a
format-normalized snapshot from JovieInc/Jovie at `065ba6ff9c06ad2de13b2297fcf48bc5e8c43035`, path
`scripts/fixtures/lyb-launch-contract.json`. It defines deadline-replan, drift,
return, and safety paths, but no numeric planner cases or rate limits. The XCTest
arithmetic cases and injected bounds are test-only examples, not physiological
policy. The parent LYB-183 retains installed-build and TestFlight evidence.
