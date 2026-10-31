# Training pricing boundary (LYB-282)

Decision: **No.** Program revision and the training-only MCP do not read a price,
check an entitlement, or call checkout, failed-payment, or cancel. This loop does
not require payment. Monetization implementation remains on LYB-48 and LYB-138.
This decision does not change the native app's existing paid access controls.

The sole machine-readable decision is
[`TRAINING_PRICING_BOUNDARY_POLICY`](../../apps/web/src/lib/training/pricing-boundary-policy.ts).
The existing web CI suite checks that it exists exactly once across production
app, package and agent sources, including renamed or JSON copies. Handler
fixtures exercise revision read/propose/apply/reject and training MCP discovery,
read and write with throwing billing spies; any invocation fails even if a handler
catches the error. Authentication, training consent, feature flags, OAuth scopes
and rate limits remain in force.

This slice adds no billing integration or payment gate. A future change to this
boundary requires an explicit policy decision and updated regression evidence.
