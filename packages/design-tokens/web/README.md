# Shared Jovie typography projection

Tim's 2026-09-04 decision: “It should be one design system across the board. So whatever Jovie uses, that's what it uses.” This supersedes the prior LYB missing-font-authority blocker. GBrain: `decisions/shared-jovie-design-system-founder-2026-09-04`.

**Boundary: compose/extend the existing token package.** Jovie's `design-system.css` and runtime font loader at revision `7641ffa76d03326542541c62080735c28190a1f0` define Inter for body/UI and Satoshi for editorial headings. The current `scripts/generate-design-tokens-export.mjs` exports colors only; private `@jovie/ui` requires Node 22 while LYB requires Node 20. This narrow projection preserves the canonical roles and unchanged font bytes without importing a second application, upgrading Node, or linking sibling checkouts.

`jovie-typography-source.json` pins upstream paths, revision, and font SHA256 values. `jovie-typography.css` projects the role aliases. The web root layout loads both bundled variable fonts through Next's local loader; global CSS consumes the aliases, and `.lyb-landing` applies the display role to headings. Aliases resolve on body because the loader variables are attached there. LYB copy, artwork, heading sizes, composition, and native tokens remain product-owned and unchanged.

The fonts are unchanged upstream web assets. Inter uses the [SIL Open Font License](https://github.com/rsms/inter/blob/master/LICENSE.txt). Satoshi is from [Fontshare](https://www.fontshare.com/fonts/satoshi), governed by the [ITF Free Font License](https://www.fontshare.com/licenses/itf-ffl), which permits web use. Full license notices are retained beside the font files. These files are unchanged and bundled for the company’s own application rendering, not offered as a font distribution service.

**Revisit trigger:** when Jovie publishes a compatible, versioned typography export with bundled faces, consume that release and retire this projection. Until then, canonical upstream font/token changes require updating the pinned receipt and passing font-hash, actual-rendered-face, responsive, and interaction checks. Do not independently redesign these values.
