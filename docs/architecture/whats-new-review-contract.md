# What’s New review contract

## Adopt-first decision

**Decision: extend and compose.** LogYourBody already had a native launch-time
What’s New sheet, an in-target changelog model, bundle version/build readers,
customer destinations, and local `UserDefaults` state. Apple TipKit is useful
for [contextual feature education](https://developer.apple.com/documentation/tipkit/highlightingappfeatureswithtipkit)
after a destination opens. [WhatsNewKit](https://github.com/SvenTiigi/WhatsNewKit)
is an MIT-licensed Swift package with SwiftUI presentation and pluggable
version stores; its latest release observed in this preflight was 2.2.1 from
April 2024 and the repository was not archived. It primarily records presented
versions and marks a version presented when its view is dismissed. Neither
option supplies LogYourBody’s exact build/destination evidence or distinct
seen/reviewed lifecycle. Adding a dependency would duplicate the existing
surface without solving that product-specific gap, while an owned value-type
contract remains easy to move into a shared package later.

The smallest boundary is therefore:

- extend the existing launch sheet and changelog model with an exact installed
  release/build contract;
- compose it with the existing paid timeline destination;
- retain local seen/reviewed state behind a small store that can later be
  replaced by a shared Jovie-owned adapter without changing product UI.

Revisit a shared package or server adapter when Jovie and Ovie both consume the
contract, cross-device acknowledgement is required, or release items need to be
updated independently of an app binary.

## Minimal cross-product contract

Every item requires:

| Field | Meaning |
| --- | --- |
| `id` | Stable product-owned change identity. |
| `product` | Lowercase product identity (`logyourbody`). |
| `version` + `build` | Exact installed binary evidence required for display. |
| `destination` | Stable customer destination (`logyourbody://timeline`). |
| `title`, `summary`, `actionTitle` | Customer-safe wording, never commit or CI copy. |
| `seen` | The exact build’s sheet was displayed. Dismissal records only this. |
| `reviewed` | The customer deliberately opened the destination. |

`seen` and `reviewed` are intentionally independent. An unreviewed item appears
again on the next app open; a reviewed item does not become new again merely
because the same code was rebuilt.

## Customer-facing hierarchy invariants

- Version and build are typed label/value fields, not one undifferentiated
  string. Labels use a distinct semantic role and visual treatment from values.
- Release metadata sits directly below “What’s New” and remains smaller and
  quieter than the title and release item.
- Spacing separates metadata fields; punctuation or high-contrast rules must
  not compete with the content hierarchy.
- Supporting copy remains visually secondary. The item title and its action are
  the only competing review choices.
- Adjacent explanatory copy must not repeat the action title or its destination.
  For example, “Opens Timeline” next to “Open timeline” is invalid.

## Proof boundary

The installed bundle supplies exact version/build provenance and the compiled
destination supplies source/runtime reachability. This does **not** prove that
the build reached TestFlight or the App Store. GitHub PRs, checks, merge state,
and deployment workflows are release-control evidence and must never be shown
as customer-visible shipping proof.

The latest separately observed distribution receipt during this preflight was
TestFlight version `1.2.0`, build `20260822231602`, from release-loop run
`32603766369` at source SHA `12d1275219d089e1af1c99384e62aba204ccf138`.
The current `main` release-loop run `32617541035` failed, so it is not current
customer distribution proof and no production configuration was changed.
