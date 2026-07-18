# LogYourBody Documentation

Product truth starts in the typed product registry, not in a page component or a marketing document.

## Start here

- [Generated product registry](product/product-registry.generated.md): brand, messaging, features, plan, reference pricing, support, and canonical surfaces.
- [Brand ethos](product/brand-ethos.md): product promise, safety boundaries, voice, and visual direction.
- [Evidence and recommendation standard](product/evidence-and-recommendation-standard.md): standards for claims and recommendations.
- [Golden path](GOLDEN_PATH.md): the paid iOS product loop.
- [User journeys](USER_JOURNEYS.md): current tested user-facing paths.

## Editing product truth

1. Change `packages/product-registry/src/products/logyourbody.mjs`.
2. Run `pnpm product:generate`.
3. Commit the registry and generated Swift/Markdown outputs together.
4. Run `pnpm product:check` plus the normal repo validation.

The package deliberately separates reusable schema/selectors from the LogYourBody definition. It is extraction-ready for a central Jovie company package; consumers should import the package instead of copying constants.
