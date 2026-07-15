# LogYourBody Style Guide

This guide defines the implementation principles and tokens used across the web product.

All visual and copy decisions must also follow the canonical [Brand Ethos](../../../docs/product/brand-ethos.md) and [Evidence and Recommendation Standard](../../../docs/product/evidence-and-recommendation-standard.md).

## Design Tokens

All colors, typography, spacing, and animation values are stored in `src/styles/design-tokens.ts`. These tokens power every component, ensuring consistency and accessibility.

## Brand Page

For the full color palette and typography details, see the [Brand Page](BRAND_PAGE.md). Use these values when creating new components or external assets so that everything aligns with our brand.

## Usage

- **Colors**: Reference tokens via helper functions (`getColor`, `tw` classes) rather than hard‑coding values.
- **Typography**: Use the predefined token styles for headings, labels, and body text.
- **Spacing**: Leverage tokenized spacing values for consistent layouts.

Maintaining these guidelines ensures that our design stays cohesive as we scale.
