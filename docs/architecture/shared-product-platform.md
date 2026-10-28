# Shared Product Platform

## Decision

LogYourBody uses `@jovieinc/product-registry` as the machine-readable source of truth for product identity, brand messaging, feature availability, entitlements, reference pricing, support options, canonical surfaces, and landing-page recipes.

The shape follows the proven Jovie registries:

- entitlement registry: plans own capabilities, limits, marketing names, and provider identifiers;
- feature registry: stable IDs distinguish shipped, beta, planned, and intentionally absent features;
- canonical surfaces: every product surface has an owner, purpose, route, and status;
- landing registry: pages are recipes composed from known sections, not bespoke one-off copy;
- terminology and brand maps: public wording comes from product data instead of page-local strings.

## Runtime flow

```text
packages/product-registry/src/products/logyourbody.mjs
                    │
          typed package build
          ┌─────────┴─────────┐
          │                   │
     Web / docs imports   generator
                              │
                    ┌─────────┴──────────┐
                    │                    │
       GeneratedProductRegistry.swift   product-registry.generated.md
                    │                    │
                 iOS app           human/agent docs
```

App Store Connect and RevenueCat remain authoritative for the localized price a customer can purchase. The registry owns expected product/package IDs, entitlement IDs, trial length, and reference USD prices used by web and documentation. Release checks must fail if provider configuration drifts from those identifiers.

## Cross-product reuse

The package separates reusable TypeScript contracts and selectors from the LogYourBody definition. A future Jovie, Ovie, or new-product entry should add another product definition rather than fork the schema or generators.

Cross-repository consumers must use a versioned package release from a central Jovie-owned product-platform repository. Filesystem symlinks between local checkouts are prohibited because they do not survive CI or clean clones. Copying this package into Jovie is also prohibited; extract and version it before the second repository consumes it.

The same rule applies to the documentation shell. Jovie's current Nextra app is the reference implementation. When the shared docs site is extracted, product repositories should supply registry data and MDX content to one versioned `@jovieinc/docs-platform` shell so navigation, search, theming, and dark-mode changes land once.

## Adding or rebranding a product

1. Add a product definition satisfying `ProductDefinition`.
2. Add its real logo assets and provider identifiers.
3. Generate native and documentation outputs.
4. Configure each app to select the product ID at build time.
5. Run the registry, drift, web, and native tests.

Do not rename the app, change prices, add a marketed feature, or promise a support channel directly in a component. Change the registry and regenerate consumers.
