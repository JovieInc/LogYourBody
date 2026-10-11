-- Run with authenticated psql; see docs/integrations/revenuecat-ledger.md.
-- Deliberately reports observed gross charges, not net revenue or store proceeds.
begin read only;
set local timezone = 'UTC';
with
params as (
  select :'app_id'::text as app_id, :'start_at'::timestamptz as start_at,
    :'end_at'::timestamptz as end_at, :'as_of'::timestamptz as as_of
),
products(product_id, months) as (
  values ('com.logyourbody.app.pro1.monthly.3daytrial', 1),
    ('com.logyourbody.app.pro1.annual.3daytrial', 12)
),
-- SIX ISO 4217 List One published 2026-09-17, verified 2026-10-09.
-- Only numeric-minor-unit entries not marked IsFund: no funds, metals, test/no-currency codes.
-- Frozen report support, not an automatic runtime fetch; see the operator documentation.
supported_currencies(code) as (
  values
    ('AED'), ('AFN'), ('ALL'), ('AMD'), ('AOA'), ('ARS'), ('AUD'), ('AWG'), ('AZN'), ('BAM'),
    ('BBD'), ('BDT'), ('BHD'), ('BIF'), ('BMD'), ('BND'), ('BOB'), ('BRL'), ('BSD'), ('BTN'),
    ('BWP'), ('BYN'), ('BZD'), ('CAD'), ('CDF'), ('CHF'), ('CLP'), ('CNY'), ('COP'), ('CRC'),
    ('CUP'), ('CVE'), ('CZK'), ('DJF'), ('DKK'), ('DOP'), ('DZD'), ('EGP'), ('ERN'), ('ETB'),
    ('EUR'), ('FJD'), ('FKP'), ('GBP'), ('GEL'), ('GHS'), ('GIP'), ('GMD'), ('GNF'), ('GTQ'),
    ('GYD'), ('HKD'), ('HNL'), ('HTG'), ('HUF'), ('IDR'), ('ILS'), ('INR'), ('IQD'), ('IRR'),
    ('ISK'), ('JMD'), ('JOD'), ('JPY'), ('KES'), ('KGS'), ('KHR'), ('KMF'), ('KPW'), ('KRW'),
    ('KWD'), ('KYD'), ('KZT'), ('LAK'), ('LBP'), ('LKR'), ('LRD'), ('LSL'), ('LYD'), ('MAD'),
    ('MDL'), ('MGA'), ('MKD'), ('MMK'), ('MNT'), ('MOP'), ('MRU'), ('MUR'), ('MVR'), ('MWK'),
    ('MXN'), ('MYR'), ('MZN'), ('NAD'), ('NGN'), ('NIO'), ('NOK'), ('NPR'), ('NZD'), ('OMR'),
    ('PAB'), ('PEN'), ('PGK'), ('PHP'), ('PKR'), ('PLN'), ('PYG'), ('QAR'), ('RON'), ('RSD'),
    ('RUB'), ('RWF'), ('SAR'), ('SBD'), ('SCR'), ('SDG'), ('SEK'), ('SGD'), ('SHP'), ('SLE'),
    ('SOS'), ('SRD'), ('SSP'), ('STN'), ('SVC'), ('SYP'), ('SZL'), ('THB'), ('TJS'), ('TMT'),
    ('TND'), ('TOP'), ('TRY'), ('TTD'), ('TWD'), ('TZS'), ('UAH'), ('UGX'), ('USD'), ('UYU'),
    ('UZS'), ('VED'), ('VES'), ('VND'), ('VUV'), ('WST'), ('XAF'), ('XCD'), ('XCG'), ('XOF'),
    ('XPF'), ('YER'), ('ZAR'), ('ZMW'), ('ZWG')
),
events as (
  select r.event_id, r.received_at, r.payload ->> 'api_version' as api_version, r.payload -> 'event' as e,
    to_timestamp((r.payload -> 'event' ->> 'event_timestamp_ms')::numeric / 1000) as event_time
  from public.revenuecat_events r, params p
  where r.app_id = p.app_id
    and to_timestamp((r.payload -> 'event' ->> 'event_timestamp_ms')::numeric / 1000) <= p.as_of
),
charge_groups as (
  select e ->> 'transaction_id' as transaction_id,
    min(event_time) as event_time,
    jsonb_agg(e order by event_time, event_id) -> 0 as e,
    count(distinct jsonb_build_array(
      e -> 'product_id', e -> 'original_transaction_id', e -> 'purchased_at_ms',
      e -> 'expiration_at_ms', e -> 'price', e -> 'price_in_purchased_currency',
      e -> 'currency', e -> 'period_type', e -> 'is_family_share'
    )) = 1 as consistent
  from events
  where api_version = '1.0' and e ->> 'environment' = 'PRODUCTION' and e ->> 'store' = 'APP_STORE'
    and e ->> 'type' in ('INITIAL_PURCHASE', 'RENEWAL')
    and e ->> 'transaction_id' is not null
  group by e ->> 'transaction_id'
),
charges as (
  select g.*, products.months, currencies.code is not null as currency_supported,
    e ->> 'original_transaction_id' as subscription_id,
    (e ->> 'price')::numeric as usd,
    (e ->> 'price_in_purchased_currency')::numeric as local_amount,
    e ->> 'currency' as currency,
    to_timestamp((e ->> 'purchased_at_ms')::numeric / 1000) as purchased_at,
    to_timestamp((e ->> 'expiration_at_ms')::numeric / 1000) as expires_at,
    (g.consistent and products.product_id is not null
      and (e ->> 'price')::numeric >= 0
      and (e ->> 'price_in_purchased_currency')::numeric >= 0
      and currencies.code is not null
      and e ->> 'is_family_share' = 'false') is true as supported
  from charge_groups g left join products on products.product_id = g.e ->> 'product_id'
    left join supported_currencies currencies on currencies.code = g.e ->> 'currency'
),
window_charges as (
  select c.* from charges c, params p
  where c.event_time >= p.start_at and c.event_time < p.end_at
),
currency_totals as (
  select currency, sum(local_amount) as amount
  from window_charges where supported group by currency
),
latest_period as (
  select c.*, dense_rank() over (
    partition by subscription_id order by purchased_at desc nulls first
  ) as period_rank
  from charges c, params p
  where subscription_id is not null and (purchased_at <= p.as_of or purchased_at is null)
),
latest_candidates as (
  select l.*, count(*) over (partition by subscription_id) as tied_periods
  from latest_period l where period_rank = 1
),
mrr_candidates as (
  select l.*,
    (l.supported and l.tied_periods = 1 and l.usd > 0
      and l.e ->> 'period_type' = 'NORMAL' and l.expires_at > p.as_of
      and l.expires_at = l.purchased_at + make_interval(months => l.months)
      and not exists (
        select 1 from events v
        where v.e ->> 'environment' = 'PRODUCTION' and v.e ->> 'store' = 'APP_STORE'
          and (v.e ->> 'transaction_id' = l.transaction_id
            or (v.e ->> 'transaction_id' is null
              and v.e ->> 'original_transaction_id' = l.subscription_id))
          and v.event_time >= l.event_time
          and (v.e ->> 'type' in ('REFUND_REVERSED', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED', 'EXPIRATION')
            or (v.e ->> 'type' = 'CANCELLATION'
              and ((v.e ->> 'price')::numeric < 0 or v.e ->> 'cancel_reason' = 'CUSTOMER_SUPPORT')))
      )) is true as mrr_supported
  from latest_candidates l, params p
),
unscoped_uncertainty as (
  -- Transfer/unknown events may lack a transaction chain. Do not guess their MRR effect.
  select count(*) as count from events
  where coalesce(e ->> 'environment', 'UNKNOWN') <> 'SANDBOX'
    and (api_version <> '1.0' or e ->> 'type' = 'TRANSFER'
      or (e ->> 'original_transaction_id' is null and e ->> 'transaction_id' is null
        and (e ->> 'type' in ('REFUND_REVERSED', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED', 'EXPIRATION')
          or (e ->> 'type' = 'CANCELLATION'
            and ((e ->> 'price')::numeric < 0 or e ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'))))
      or e ->> 'type' not in (
      'TEST', 'INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION', 'UNCANCELLATION',
      'NON_RENEWING_PURCHASE', 'EXPIRATION', 'BILLING_ISSUE', 'PRODUCT_CHANGE',
      'SUBSCRIPTION_EXTENDED', 'REFUND_REVERSED', 'SUBSCRIPTION_PAUSED'
    ))
)
select jsonb_build_object(
  'app_id', p.app_id, 'start_at', p.start_at, 'end_at', p.end_at, 'as_of', p.as_of,
  'earliest_received_at', (select min(received_at) from events),
  'observed_gross_purchase_usd', (select coalesce(sum(usd), 0) from window_charges where supported),
  'observed_gross_by_currency', (select coalesce(jsonb_object_agg(currency, amount), '{}'::jsonb) from currency_totals),
  'supported_charge_count', (select count(*) from window_charges where supported),
  'unsupported_currency_charge_count', (select count(*) from window_charges where not currency_supported),
  'unsupported_charge_count', (select count(*) from window_charges where not supported),
  'conflicting_transaction_count', (select count(*) from window_charges where not consistent),
  'supported_observed_mrr_usd', case when (select count from unscoped_uncertainty) > 0 then null
    else (select coalesce(sum(usd / months), 0) from mrr_candidates where mrr_supported) end,
  'excluded_mrr_period_count', (select count(*) from mrr_candidates where not mrr_supported),
  'unkeyed_subscription_charge_count', (select count(*) from charges where subscription_id is null),
  'unscoped_mrr_event_count', (select count from unscoped_uncertainty),
  'sandbox_or_test_event_count', (select count(*) from events where e ->> 'environment' = 'SANDBOX' or e ->> 'type' = 'TEST' or e ->> 'store' = 'TEST_STORE'),
  'unclassified_environment_event_count', (select count(*) from events where coalesce(e ->> 'environment', 'UNKNOWN') not in ('PRODUCTION', 'SANDBOX')),
  'unsupported_api_version_event_count', (select count(*) from events where api_version <> '1.0'),
  'unsupported_store_event_count', (select count(*) from events where coalesce(e ->> 'store', 'UNKNOWN') not in ('APP_STORE', 'TEST_STORE')),
  'non_charge_lifecycle_event_count', (select count(*) from events where e ->> 'type' not in ('INITIAL_PURCHASE', 'RENEWAL', 'TEST')),
  'unkeyed_purchase_event_count', (select count(*) from events where e ->> 'type' in ('INITIAL_PURCHASE', 'RENEWAL') and e ->> 'transaction_id' is null),
  'refund_or_reversal_event_count', (select count(*) from events where e ->> 'type' = 'REFUND_REVERSED' or (e ->> 'type' = 'CANCELLATION' and ((e ->> 'price')::numeric < 0 or e ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'))),
  'net_revenue_usd', null, 'financial_reconciliation_complete', false,
  'coverage_note', 'Observed events only. Gross charges exclude unsupported data; MRR excludes ambiguous or nonstandard periods. No net revenue or complete-history claim.'
) as revenue_summary
from params p where p.start_at < p.end_at and p.end_at <= p.as_of;
commit;
