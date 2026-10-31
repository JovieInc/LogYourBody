/** Sole pricing decision for program revision and training-only MCP (LYB-282).
 * Monetization remains owned by LYB-48 / LYB-138, outside this loop.
 */
export const TRAINING_PRICING_BOUNDARY_POLICY = Object.freeze({
  readPrice: false,
  checkEntitlement: false,
  checkout: false,
  failedPayment: false,
  cancel: false,
} as const);
