# Client qualification order (LYB-275)

Recorded November 1, 2026. Parent: LYB-163. Depends on LYB-161. **Accepted
default** under the issue's "ships if unanswered" instruction. The
[decision record](client-qualification-order.json) is the authorization source.
The [roadmap](../../../docs/product-development-roadmap.md#lyb-275-client-qualification-order)
carries the same boundary. The
[LYB-163 runbook](../../../docs/integrations/chatgpt-app/client-qualification.md)
still owns the qualification matrix, receipt protocol, and CLI decision.

Question: who provides the consented test accounts and client registrations,
and in what order do Claude Code, ChatGPT, and Jovie get qualified?

Decision: qualify Claude Code first on a synthetic fixture account only, with
no real user data, then ChatGPT, then Jovie. Real consented accounts and client
registrations are not provided. The account owner supplies them only after that
client's synthetic run passes. This record does not connect an account, register
a client, store a credential, or add an admission label.

No client is qualified by this decision. A synthetic pass does not qualify
another client and does not authorize a real account connection. The October 13
TestFlight beta, the held release PR, and the in-flight TestFlight delivery stay
grandfathered. Real-device TestFlight evidence stays with LYB-161. Slice keys
are repository-local identifiers, not Linear issue IDs, admission labels, or
dispatch.

## Accounts and registrations provided

This decision provides two synthetic fixtures and nothing else. They are aliases
for the runbook's isolated subjects A and B. They carry no credentials, no
client ID, no redirect URI, and no real user data. Health values, tokens, and
throwaway signing keys stay in isolated test memory and are not committed.

| ID        | Kind              | Role      | Provided by | Real user data | Credentials |
| --------- | ----------------- | --------- | ----------- | -------------- | ----------- |
| fixture-a | synthetic fixture | subject A | LYB-275     | no             | none        |
| fixture-b | synthetic fixture | subject B | LYB-275     | no             | none        |

Not provided, for Claude Code, ChatGPT, and Jovie alike:

- Consented test accounts. Provider: the account owner (Tim, who supplies
  secret values out of band). Available only after that client's synthetic run
  passes. Production customer records are never fixtures.
- OAuth client registrations and exact approved redirect URIs. Provider: the
  same account owner, one registration per client, coordinated with JOV-7796.
  A registration for one client does not cover the others.

Agents do not create, invent, store, or connect those accounts or registrations.

## Provider steps

1. A later qualification slice runs the synthetic protocol for one client, using
   fixture-a and fixture-b only. That step has not been run.
2. After that client's synthetic run passes, the account owner provides the
   consented nonproduction account, the public client ID, and the exact approved
   redirect. Those items are not provided.
3. Hosted-client policy review and any real-account qualification stay with the
   account owner. This decision accepts neither.

## Child slices

### Slice: Claude Code

Key: `claude_code`. Order: 1. Implementation: `authorized_synthetic_fixture_only`.

Claude Code is first. It may start from this record, and only on fixture-a and
fixture-b. Follow the LYB-163 synthetic protocol: isolated storage, throwaway
signing keys that are not committed, and no production records. Do not register
a client or connect an account. A consented account, public client ID, and exact
redirect stay unprovided until the account owner supplies them after this
client's synthetic run passes. This record does not run the qualification
(`implemented` stays false). Claude Code's result does not qualify ChatGPT or
Jovie.

### Slice: ChatGPT

Key: `chatgpt`. Order: 2. Implementation: `authorized_after_claude_code_synthetic_passes`.

ChatGPT starts after the Claude Code synthetic run passes. It then uses the same
synthetic fixtures only. Claude Code's pass, an SDK harness, and vault-sharing
consent do not qualify ChatGPT or approve weight disclosure. Its registration
and consented account are not provided. The account owner supplies that client's
own registration and account only after the ChatGPT synthetic run passes. Hosted
policy review stays pending. This record gives the slice no executed
qualification.

### Slice: Jovie

Key: `jovie`. Order: 3. Implementation: `authorized_after_chatgpt_synthetic_passes`.

Jovie starts after the ChatGPT synthetic run passes. It then uses the same
synthetic fixtures only. A Jovie `sub` is not an LYB connection, and a fleet
service token is not a customer. Session ownership, retention, and connection
gates stay independent and unproven. Its registration and consented account are
not provided. The account owner supplies them only after the Jovie synthetic run
passes. This record gives the slice no executed qualification.
