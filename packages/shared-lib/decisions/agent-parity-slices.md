# Agent parity slices beyond LYB-162 (LYB-274)

Recorded November 1, 2026. Parent: LYB-161. Depends on LYB-162. **Accepted
default** under the issue's "ships if unanswered" instruction. The
[decision record](agent-parity-slices.json) is the authorization source. The
[roadmap](../../../docs/product-development-roadmap.md#lyb-274-next-slice-only)
carries the same boundary.

Question: may agents start implementing agent-parity slices after LYB-162, or
does the planning-only restriction stand?

Decision: authorize the next slice only. After the current TestFlight release
ships, agents may add a CI parity-inventory check. Every iOS capability in the
[canonical inventory](../../../docs/integrations/chatgpt-app/README.md#canonical-ios-capability-inventory)
maps to a product API or MCP action, or to a declared device, system, or user
handoff. That check is not feature work. The planning-only restriction stands
for the other six slices below.

The October 13 TestFlight beta, the held release PR, and the in-flight
TestFlight delivery stay grandfathered. These slices do not gate them. LYB-162
remains the in-progress weight slice. Real-device TestFlight evidence stays
with LYB-161. Slice keys are repository-local identifiers, not Linear issue
IDs, admission labels, or dispatch.

Out of scope for these slices: training, voice, client qualification, daily
step records, weight-lifecycle changes, account connection, deployment,
marketplace publication, and release metadata.

## Child slices

### Slice: Inventory check

Key: `inventory_check`. Implementation: `authorized_after_current_testflight_ships`.

Start only after the current TestFlight release ships. This decision does not
certify that shipment and does not add the check (`implemented` stays false).

When it starts, add one CI check over the canonical inventory table. Each data
row passes when its product-action column names an API or MCP action, or a
declared device, system, or user handoff. A row with neither fails. Source
availability, a tool response, and a local dialog do not establish parity or
completion. Keep the grandfathered beta, the in-flight TestFlight delivery, and
LYB-162 ungated. Add no tool, route, scope, account connection, or feature
behavior in order to make the check pass.

### Slice: Goals and preferences

Key: `goals_preferences`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: typed read, update, and reset for
selected targets and preferences on the profile, units, goals, dated outcomes,
and preferences inventory row. Keep measured values, estimates, and selected
targets distinct. Preserve safety restrictions and device-local settings
boundaries. Revisions and explicit units and timezone stay part of that future
contract. This record gives that work no implementation authority.

### Slice: Trends

Key: `trends`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: deterministic read summaries for
latest metrics, history, trends, interpolation, and body score, with dates,
units, method and version, missingness, and provenance. Timeline navigation and
visual rendering may hand off to the app. The summary uses the existing
deterministic methods and discloses no health data automatically. This record
gives that work no implementation authority.

### Slice: Photos and imports

Key: `photos_imports`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: owned photo and import-job actions
for progress-photo capture, selection, attach, review, edit, delete, and bulk
import, plus DEXA, InBody, PDF, and BodySpec imports. Camera and library
selection and local processing need device permission and completion receipts.
Raw photos stay out of ordinary MCP results. Import work extends LYB-80 only
under a later authorization: source authorization, preview and confirm,
deduplication, correction, and persisted readback. Parsing counts alone are not
ingestion. This record gives that work no implementation authority.

### Slice: GLP-1

Key: `glp1`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: owned read, create, correct, and
delete for GLP-1 dose and check-in history, with units, observation time, and
provenance. Daily step records are a separate inventory concern and are outside
this slice. GLP-1 and other medical records stay off the training MCP server
until a separately approved health-data contract exists; until then the
supported boundary is an authorized native handoff. This record is not that
health-data approval and gives the slice no implementation authority.

### Slice: Export and deletion

Key: `export_deletion`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: explicit confirmation, a
subject-scoped export or deletion request and status, and a durable completion
receipt for the export, metric and photo sharing, and account-deletion
inventory row. The native share sheet and file delivery stay device handoffs.
Revoke and delete have to prevent in-flight retries and offline pushes from
restoring erased data, within the existing retention and health-data policy.
This record gives that work no implementation authority.

### Slice: Integration status

Key: `integration_status`. Implementation: `not_authorized`.

Scope, if a later decision authorizes it: read integration availability through
the existing [integration-status semantics](../../../docs/architecture/native-integration-status.md).
Keep configuration, per-user connection, permission, history, and last verified
sync or error distinct. Reconnect, revoke, and support submission require an
explicit user action. Opening a link is an offered handoff, and provider
completion still needs its own receipt. This record gives that work no
implementation authority.
