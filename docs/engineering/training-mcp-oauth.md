# Training MCP OAuth boundary (LYB-280)

Decision: use the existing Jovie Better Auth issuer and exactly
`lyb:training.read` and `lyb:training.write` for the training-only MCP. Its feature
flag defaults **off**.

The executable allowlist is
[`LYB_TRAINING_MCP_SCOPES`](../../apps/web/src/lib/mcp/contract.ts).
Training tool permissions and default protected-resource metadata use that same
definition. Metrics and health-vault scopes belong to their separate gated
capabilities; they do not extend the training-only allowlist.

The server continues to use `oauthIssuer()` and its public JWKS, shared with the
existing Jovie OAuth integration. This decision does not introduce an identity
provider or change token issuance. Issuer-side registration remains external work
described in the [MCP integration guide](../integrations/chatgpt-app/README.md).

[`trainingMcpEnabled`](../../apps/web/src/lib/flags/training-mcp.ts) keeps admission
closed unless both `LYB_CHATGPT_MCP_ENABLED` and
`LYB_HYPERTROPHY_COACH_API_ENABLED` equal the literal string `true`. Missing, false,
or malformed values stay off. The production MCP dependency wiring uses this
function; it preserves the existing rollout switches.

The required web test suite asserts the exact scope allowlist, the default Jovie
issuer in training metadata, and default-off admission. The existing Gitleaks
security workflow scans PR and merge-group changes for committed tokens, client
secrets, and private keys. No credentials are needed for this contract or its tests.

Store submission, linked-account milestones, and monetization (LYB-48) remain
outside this decision.
