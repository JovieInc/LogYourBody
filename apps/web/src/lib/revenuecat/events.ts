import { z } from 'zod';

const identifier = z.string().min(1).max(512);
const optionalIdentifier = identifier.nullable().optional().default(null);
const timestamp = z.number().int().min(0).max(8_640_000_000_000_000);
const optionalTimestamp = timestamp.nullable().optional().default(null);
const amount = z
  .number()
  .finite()
  .min(-1_000_000_000)
  .max(1_000_000_000)
  .nullable()
  .optional()
  .default(null);

/** Persist only reporting fields; subscriber attributes and unknown personal data are omitted. */
export const revenueCatEnvelopeSchema = z.object({
  api_version: identifier,
  event: z.object({
    id: identifier,
    app_id: identifier,
    type: identifier,
    event_timestamp_ms: timestamp,
    environment: optionalIdentifier,
    store: optionalIdentifier,
    transaction_id: optionalIdentifier,
    original_transaction_id: optionalIdentifier,
    app_user_id: optionalIdentifier,
    original_app_user_id: optionalIdentifier,
    product_id: optionalIdentifier,
    period_type: optionalIdentifier,
    purchased_at_ms: optionalTimestamp,
    expiration_at_ms: optionalTimestamp,
    // Preserve unknown codes for the ledger; the SQL report separately checks monetary eligibility.
    currency: z
      .string()
      .regex(/^[A-Z]{3}$/)
      .nullable()
      .optional()
      .default(null),
    price: amount,
    price_in_purchased_currency: amount,
    is_family_share: z.boolean().nullable().optional().default(null),
    cancel_reason: optionalIdentifier,
    expiration_reason: optionalIdentifier,
    new_product_id: optionalIdentifier,
  }),
});

export type RevenueCatEnvelope = z.infer<typeof revenueCatEnvelopeSchema>;
