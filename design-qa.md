# Landing page design QA

Final result: passed

## Source and implementation

- Mobile source: `/Users/timwhite/.codex/generated_images/019f6294-2090-7d70-a1e8-0ee7462a409a/exec-c45a1942-1587-4dc3-948e-f0191f949c35.png`
- Desktop source: `/Users/timwhite/.codex/generated_images/019f6294-2090-7d70-a1e8-0ee7462a409a/exec-6c68bed7-43fb-409e-b605-a815577361d3.png`
- Mobile implementation: `docs/audits/landing-page/mobile-men-recomposition.png`
- Desktop implementation: `docs/audits/landing-page/desktop-women-recomposition.png`
- Combined mobile comparison: `docs/audits/landing-page/comparison-mobile.png`
- Combined desktop comparison: `docs/audits/landing-page/comparison-desktop.png`

The mobile comparison uses the top 390 × 844 state from the long-form source and
the implementation at the same viewport. The desktop comparison normalizes the
source and implementation to the same 16:10 frame.

## Required fidelity surfaces

- One dark, navigation-free conversion surface.
- Two-line mobile promise, restrained supporting copy, pill email field, and pill CTA.
- Conversion controls stacked on mobile and inline on desktop.
- Editorial performance photo visible only at the desktop breakpoint.
- Real iOS product capture, not a reconstructed marketing dashboard.
- Stable geometry across men and women audience variants.

The real Fastlane capture is intentionally taller and more detailed than the
primitive source mock. This is the required truthful deviation: the landing page
inherits the current app capture instead of preserving invented UI.

## Fix history

1. P1 — The first desktop capture placed the editorial image behind the isolated
   page background. The image and gradient were moved into positive stacking
   layers and content was given an explicit foreground layer.
2. P1 — The desktop headline's intrinsic width expanded the first grid column and
   pushed product evidence off-canvas. Grid children now use `min-w-0`, the
   headline has a bounded measure, and the product capture has a stable width.
3. P2 — Empty submission exposed an error but did not return focus to the email
   field. Focus now follows the live validation state and is covered in unit and
   browser checks.
4. P2 — The first mobile composition placed the signal line before product proof.
   Mobile now follows the source rhythm: promise, capture, then the supporting
   signal line; desktop keeps the line beside the editorial image.

Post-fix evidence is recorded in both combined comparison images. No actionable
P0, P1, or P2 findings remain.

## Browser evidence

- In-app browser: Codex browser runtime.
- Mobile: 390 × 844, men/recomposition and men/fat-loss.
- Desktop: 1440 × 900, women/recomposition.
- Horizontal overflow: 0 px at both viewports.
- Navigation links: 0.
- Mobile editorial photo: not rendered in the visible layout.
- Desktop controls: input and CTA share one row and have 58 px targets.
- Invalid submit: live error appears, `aria-invalid=true`, and focus returns to
  `waitlist-email-v2`.
- Console: 0 errors and 0 warnings after the image sizing correction.
- SEO/AEO: canonical URL, campaign-safe Open Graph image, and truthful
  `SoftwareApplication` JSON-LD were present in the rendered document.
- Reduced motion: the component resolves every entrance transition to zero when
  `prefers-reduced-motion` is active; the forced reduced-motion render is covered
  by the component suite.

Success, existing-email, server-error, and attribution payload states are verified
with isolated request mocks so QA does not pollute the pre-launch waitlist.
