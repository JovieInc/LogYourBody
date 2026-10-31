# Training outbound policy (LYB-281)

Decision: **No.** Program revisions and training MCP v1 responses return
structured records only. They may neither include a prose coach message nor
initiate a message, notification, push, send, or chat post to the user, ChatGPT,
Grok, or Muse. No recipient, authority grant, or training permission enables an
exception to this default.

The sole executable policy is
[`TRAINING_OUTBOUND_POLICY`](../../apps/web/src/lib/training/outbound-policy.ts).
Its shared schema guard rejects message and delivery fields in raw records at
every nesting level, including arrays and revision diffs, before schema parsing
can discard unknown keys. Both revision proposal/receipt versions, stored
revisions, and the existing [training MCP v1 field schemas](training-mcp-field-allowlist.md)
use that guard. Existing audit reasons, evidence and deterministic engine
explanations are structured record data; they grant no message-delivery authority.

The required web test suite reads the policy, rejects missing and duplicated
definitions across production sources, and exercises structured revision and MCP
fixtures with forbidden fields injected at every object boundary.

This decision adds no delivery mechanism or rollout switch. Existing feature gates
remain in place. On-device chat send, retry and response behavior and integration
of the broader legacy MCP transport stay on LYB-72. Proactive physique messaging
stays on LYB-128. This slice does not change either flow.
