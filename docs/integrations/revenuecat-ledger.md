# RevenueCat delivery ledger (LYB-134)

This receiver records signed RevenueCat events and supplies an operator SQL report.
It does not change entitlements, purchases, products, prices or customer accounts.
There is no public revenue read API.

## Enable after review

Proposed production URL: `https://www.logyourbody.com/api/webhooks/revenuecat`.
This document does not establish that the route is deployed or configured.

1. Verify the current RevenueCat project, App Store app ID and webhook plan access.
2. Deploy the reviewed migration through the normal Neon migration/deployment path.
   Runtime writes use the existing server `DATABASE_URL`; the ledger is not part
   of native sync or customer export APIs.
3. Create or update the intended app-scoped webhook integration and enable HMAC
   signing. Set its signing secret through the normal server secret flow as
   `REVENUECAT_WEBHOOK_SIGNING_SECRET`. Set the verified dashboard app ID in
   `REVENUECAT_WEBHOOK_APP_IDS` (comma-separated if explicitly covering several apps).
   Both settings are required; an unconfigured receiver returns 503.
4. Include sandbox and production deliveries and the required lifecycle events.
   Do not paste secrets into this document, logs, issue comments or fixtures.

The receiver checks `X-RevenueCat-Webhook-Signature` against timestamp plus the
exact raw body, with a five-minute request-signing tolerance and constant-time
comparison. It does not accept an Authorization header instead of HMAC. The body
limit is 128 KiB, measured while reading, regardless of Content-Length. An
app outside the allowlist is rejected. RevenueCat re-signs each retry; the payload's
event timestamp may be old. Return 200 only after a durable insert or confirmed
duplicate. Storage errors return 503; conflicting reuse of an event ID returns 409
without replacing the original. Non-200 deliveries are retried by RevenueCat, so
investigate persistent failures before retries exhaust.
[Official authentication and retry contract](https://www.revenuecat.com/docs/integrations/webhooks)

## Event and money identities

The immutable key is `(app_id, event.id)`. The fingerprint covers normalized stored
fields, not whitespace or unknown subscriber attributes. Unknown fields are not
stored; unknown event types, nullable monetary fields and sandbox data are retained
when the required signed envelope and app ID are valid. Missing required identity,
invalid known field types, invalid currency syntax, or amounts that are nonfinite
or outside the -1 billion to +1 billion parser bounds return 400. Subscriber attributes, authorization and secrets are never
stored. A retry with different known event fields conflicts rather than rewriting history.

Financial deduplication is separate: the query counts one supported charge per
App Store production transaction ID. Different events for a purchase, cancellation
and refund remain separate rows. Renewals must not be deduplicated by original
transaction ID. Restore/transfer is not an additional payment.
[Event identity, price and refund fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)

## Authenticated operator report

Use an existing authorized PostgreSQL connection. The SQL starts a read-only
transaction; do not run it inside an existing transaction. There is no new admin
role model or credential. From the repository root in an authenticated `psql`
session, set explicit UTC boundaries and the verified app ID, for example:

```sql
\set app_id 'your-verified-dashboard-app-id'
\set start_at '2026-10-09T00:00:00Z'
\set end_at '2026-10-09T12:00:00Z'
\set as_of '2026-10-09T12:00:00Z'
\i apps/web/db/queries/revenuecat-summary.sql
```

`start_at < end_at <= as_of` is required; otherwise no report row is returned.
Today means UTC midnight through the selected current time. Revenue is attributed
to the earliest observed provider event time for a transaction, not arrival order.
The report covers only this ledger's observed history and identifies its earliest
receipt. It cannot prove that all earlier provider events were delivered.

- `observed_gross_purchase_usd` uses actual provider USD prices of supported
  production App Store initial purchases/renewals. Local amounts are aggregated
  independently in `observed_gross_by_currency`; currencies are never added together.
  Registry reference prices are not a fallback. Contradictory charge evidence is
  excluded and counted. Trials with zero price contribute zero.
- Supported charges need both prices, currency, a transaction ID, explicit non-family
  status, and a recognized monthly/annual product. Missing/unknown data, other stores,
  nonrenewing purchases and other event types remain in the ledger. Exclusion counts
  distinguish unsupported charges, missing transaction/environment, other stores and
  non-charge lifecycle events. Sandbox and TEST events never enter production totals.
- Currency syntax alone does not qualify a charge. The SQL's fixed allowlist contains
  155 monetary currency codes from the official SIX ISO 4217 List One published
  2026-09-17 and verified 2026-10-09: entries with a numeric minor unit and without
  `IsFund="true"`. Funds, metals, accounting units, `XTS`, `XXX`, unrecognized codes
  such as `ZZZ`, missing codes and withdrawn currencies are excluded from both
  gross and MRR calculations. `unsupported_currency_charge_count` counts affected
  window charges; the ledger still retains them. Valid currencies remain separate,
  including zero- and three-decimal currencies; no exchange rate or amount is invented.
  Review the allowlist against the maintenance source when supporting a new or changed
  currency. It is not fetched at runtime and does not establish historical-currency
  reconciliation.
  [Official ISO 4217 maintenance source](https://www.six-group.com/en/products-services/financial-information/market-reference-data/data-standards.html),
  [List One XML](https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml).
- `supported_observed_mrr_usd` uses the latest unambiguous paid period in each original
  transaction chain. It requires NORMAL period type, positive actual price, a known
  monthly/annual product, unexpired access and an exact calendar-month/year duration.
  An annual full-period price is divided by 12. Trials, introductory/prorated periods,
  missing chain/price/duration, equal-time competing periods and relevant refund,
  expiry, extension or product-change evidence are excluded.
  `unkeyed_subscription_charge_count` separately identifies charges whose missing
  original transaction ID prevents selecting a subscription period. Unscoped transfers,
  unknown event types/API versions or lifecycle changes without a transaction chain make the
  MRR result null rather than guessing. Auto-renew cancellation alone does not erase
  unexpired paid value. The two SQL product IDs mirror the product registry and need
  review if products change; no prices are embedded in the query.
- `net_revenue_usd` is deliberately null and `financial_reconciliation_complete`
  is false. Refund/reversal events are counted for inspection, not silently summed.
  Partial refunds, reversals, refunds for unobserved purchases and missing-price
  cases require reconciliation. Earlier-period subscription refunds may not produce
  webhooks. This is neither complete financial accounting nor App Store proceeds.

[RevenueCat MRR definition](https://www.revenuecat.com/docs/dashboard-and-metrics/charts/monthly-recurring-revenue-mrr-chart),
[lifecycle ordering](https://www.revenuecat.com/docs/integrations/webhooks/event-flows),
[refund payload examples](https://www.revenuecat.com/docs/integrations/webhooks/sample-events).

## Local and provider qualification

Focused Jest tests cover signing, malformed/oversized requests, app isolation,
immutable/concurrent replay, conflict detection, retained lifecycle/sandbox events
and acknowledgement only after persistence. For actual PostgreSQL semantics, use
already installed binaries (no downloads or external database):

```bash
python3 apps/web/db/tests/verify-revenuecat-report.py --postgres-bin /path/to/postgresql/bin
```

The script creates and removes its own temporary cluster with a private Unix socket,
no TCP listener and synthetic data. It ignores DATABASE_URL and existing PG settings.
It checks migration execution, concurrent insertion, distinct-event charge duplicates,
out-of-order lifecycle events, currency separation, trial/proration/missing-price
exclusions, refund handling and conservative MRR. It never targets a provider database.

Provider acceptance is still separate: a dashboard TEST delivery, an authorized
TestFlight sandbox purchase, a verified stored event within minutes, a resend that
does not add a charge, retained sandbox rows excluded from production totals, and an
authenticated query receipt. Configuration, purchases, production migrations and
those receipts are not established by local tests or this document. No complete
financial reconciliation claim should be made from this bounded integration.
