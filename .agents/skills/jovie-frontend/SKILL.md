---
name: jovie-frontend
description: Apply Jovie's repository frontend design contract to LogYourBody UI implementation, review, and Pen design work, preserving native platform conventions and the existing product scope.
---

# Jovie frontend

Use this skill for frontend design, UI implementation, visual review, and Pen
work on LogYourBody. Installation alone does not authorize design changes.

## Source

Jovie defines its product frontend skill as `DESIGN.md`, `.claude/rules/ui.md`,
and `docs/llms-design-manifest.txt` in
[PR #15923](https://github.com/JovieInc/Jovie/pull/15923).
This entry point packages those repository documents and their principal
references at revision `d0375abd6692770d4ae41128ce79d608cb42e822`.
It does not contain or claim to reproduce the separate desktop
`frontend-skill v2.1.1` or the external `design-taste-frontend` skill.
See [SOURCE.json](SOURCE.json) for file identities, hashes, and link adaptations.

## Read for the task

1. Read the destination repository's `AGENTS.md` and scoped guidance first.
2. Read [Jovie DESIGN.md](references/upstream/DESIGN.md).
3. Read the applicable sections of the
   [UI contract](references/upstream/.claude/rules/ui.md) and
   [design details](references/upstream/docs/design-system/DETAILS.md).
4. Use the [generated design manifest](references/upstream/docs/llms-design-manifest.txt)
   and [token documentation](references/upstream/docs/DESIGN_TOKENS.md) as
   versioned Jovie reference material. Load other references only as needed.

## Apply to LogYourBody

- Follow the user's task, LYB's `AGENTS.md`, product scope, and current native
  design owners. Map Jovie's shared design principles to those existing owners;
  this skill does not authorize replacing LYB's tokens, font, navigation, or
  product identity with Jovie's web implementation.
- For SwiftUI, retain system typography, native controls, Dynamic Type,
  accessibility, and the current `apps/ios/LogYourBody/DesignSystem/Theme.swift`
  and `packages/design-tokens` sources. For web work, inspect the destination's
  actual components and dependencies before applying a Jovie-specific pattern.
- Paths, imports, commands, component names, Pen node IDs, and historical locks
  inside the upstream documents refer to Jovie at the pinned revision. They
  are not assertions that those resources exist in LYB. Follow a pinned source
  link for context; use LYB's real equivalents for implementation and checks.
- Enumerate the states affected by the requested change, reuse the owning
  component, preserve context and interaction geometry, and verify the actual
  rendered result with the destination's appropriate tests and visual evidence.
  Keep implementation, design proposal, verification, and release claims distinct.

## Apply in Pen

- Keep the current canonical document and its referenced assets together.
  Inspect active document identity and current ownership before a mutation.
- A user-owned canvas stays untouched until design work is authorized. Do not
  switch, recreate, save over, or redesign a document to validate this install.
- Use Pen's installed canvas instructions for tool syntax. This skill supplies
  design guidance; it does not replace Pen's native tooling skill.

## Updates

Keep a single repository-owned package here. Claude's discovery entry points
to this directory; Pen registers this exact `SKILL.md` through its custom-skill
mechanism. Do not install a second copy into Pen's replaceable vendor directory.
Refresh all selected upstream files from one reviewed Jovie revision, record
their Git blob IDs, update link adaptations and hashes, then validate discovery
and references. Do not hand-edit the generated manifest or silently track main.
