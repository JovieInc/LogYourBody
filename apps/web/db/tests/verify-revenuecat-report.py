#!/usr/bin/env python3
"""Exercise the real ledger/report in a disposable, socket-only PostgreSQL cluster.

Requires existing PostgreSQL binaries; never downloads software or uses DATABASE_URL.
"""
import argparse
import concurrent.futures
import datetime
import getpass
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--postgres-bin', required=True, type=Path)
    args = parser.parse_args()
    web = Path(__file__).resolve().parents[2]
    registry = (web.parents[1] / 'packages/product-registry/src/products/logyourbody.mjs').read_text()
    query = (web / 'db/queries/revenuecat-summary.sql').read_text()
    product_ids = set(re.findall(r"productId: '([^']+)'", registry))
    assert all(query.count("'" + product + "'") == 1 for product in product_ids), 'SQL product map differs from canonical registry'
    env = {key: value for key, value in os.environ.items() if not key.startswith('PG')}
    env.pop('DATABASE_URL', None)
    env['PGCONNECT_TIMEOUT'] = '5'

    def run(command):
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout

    with tempfile.TemporaryDirectory(prefix='lyb-revenuecat-postgres-') as directory:
        root = Path(directory)
        data, socket = root / 'data', root / 'socket'
        socket.mkdir(mode=0o700)
        run([str(args.postgres_bin / 'initdb'), '-D', str(data), '-A', 'trust', '--no-locale', '-U', getpass.getuser()])
        control = [str(args.postgres_bin / 'pg_ctl'), '-D', str(data)]
        run(control + ['-l', str(root / 'postgres.log'), '-o', f"-c listen_addresses='' -k {socket} -p 6549", '-w', 'start'])
        try:
            client = [str(args.postgres_bin / 'psql'), '-X', '-q', '-A', '-t', '-h', str(socket), '-p', '6549', '-U', getpass.getuser(), '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
            run(client + ['-f', str(web / 'db/migrations/20261010010000_revenuecat_events.sql')])

            def sql(statement):
                return run(client + ['-c', statement]).strip()

            def millis(value):
                return int(datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp() * 1000)

            def event(identity, **changes):
                result = dict(id=identity, app_id='app-fixture', type='INITIAL_PURCHASE', environment='PRODUCTION', store='APP_STORE',
                              event_timestamp_ms=millis('2026-10-09T10:00:00Z'), purchased_at_ms=millis('2026-10-09T10:00:00Z'),
                              expiration_at_ms=millis('2026-11-09T10:00:00Z'), transaction_id=identity, original_transaction_id=identity,
                              app_user_id='synthetic-user', product_id='com.logyourbody.app.pro1.monthly.3daytrial',
                              period_type='NORMAL', price=10, price_in_purchased_currency=9, currency='EUR', is_family_share=False)
                result.update(changes)
                return result

            def quote(value):
                return "'" + value.replace("'", "''") + "'"

            def insert(value, api_version='1.0'):
                payload = json.dumps(dict(api_version=api_version, event=value), sort_keys=True)
                fingerprint = hashlib.sha256(payload.encode()).hexdigest()
                return sql('insert into public.revenuecat_events(app_id,event_id,fingerprint,payload) values (' +
                           ','.join(quote(item) for item in [value['app_id'], value['id'], fingerprint, payload]) +
                           ') on conflict (app_id,event_id) do nothing returning event_id;')

            def report():
                result = run(client + ['-v', 'app_id=app-fixture', '-v', 'start_at=2026-10-09T00:00:00Z',
                                       '-v', 'end_at=2026-10-09T12:00:00Z', '-v', 'as_of=2026-10-09T12:00:00Z',
                                       '-f', str(web / 'db/queries/revenuecat-summary.sql')])
                return json.loads(result)

            monthly = event('monthly', original_transaction_id='monthly-chain', type='RENEWAL')
            annual = event('annual', product_id='com.logyourbody.app.pro1.annual.3daytrial', price=120,
                           price_in_purchased_currency=120, currency='USD', expiration_at_ms=millis('2027-10-09T10:00:00Z'))
            baseline = [monthly, annual,
                        event('previous-month', original_transaction_id='monthly-chain', event_timestamp_ms=millis('2026-09-09T10:00:00Z'),
                              purchased_at_ms=millis('2026-09-09T10:00:00Z'), expiration_at_ms=millis('2026-10-09T10:00:00Z')),
                        {**monthly, 'id': 'same-charge-different-event'},
                        event('sandbox', environment='SANDBOX', price=999),
                        event('dashboard-test', type='TEST'),
                        {**monthly, 'id': 'unsubscribe', 'type': 'CANCELLATION', 'cancel_reason': 'UNSUBSCRIBE'},
                        event('other-app', app_id='other-app')]

            def reset(extra=()):
                sql('truncate public.revenuecat_events;')
                # Reverse delivery order deliberately; arrival order cannot select financial state.
                for value in reversed(baseline + list(extra)):
                    insert(value)

            reset()
            first = report()
            assert first['observed_gross_purchase_usd'] == 130, first
            assert first['observed_gross_by_currency'] == {'EUR': 9, 'USD': 120}, first
            assert first['supported_charge_count'] == 2 and first['supported_observed_mrr_usd'] == 20, first
            assert first['sandbox_or_test_event_count'] == 2 and first['net_revenue_usd'] is None, first
            assert first['financial_reconciliation_complete'] is False, first
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                assert list(pool.map(insert, [monthly, monthly])) == ['', '']
            assert report() == first
            insert({**monthly, 'price': 999})
            assert report() == first, 'Conflicting same-event insertion overwrote immutable payload'
            sql('truncate public.revenuecat_events;')
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(insert, [monthly, monthly]))
            assert sorted(results) == ['', 'monthly'], results
            assert sql('select count(*) from public.revenuecat_events;') == '1'

            reset([event('missing-price', price=None), event('trial', price=0, price_in_purchased_currency=0, period_type='TRIAL'),
                   event('prorated', price=5, price_in_purchased_currency=4, expiration_at_ms=millis('2026-10-23T10:00:00Z'))])
            value = report()
            assert value['observed_gross_purchase_usd'] == 135 and value['supported_observed_mrr_usd'] == 20, value
            assert value['unsupported_charge_count'] == 1 and value['excluded_mrr_period_count'] == 3, value

            reset([{**monthly, 'id': 'changed-charge-evidence', 'price': 11}])
            value = report()
            assert value['observed_gross_purchase_usd'] == 120 and value['conflicting_transaction_count'] == 1, value
            assert value['supported_observed_mrr_usd'] == 10, value

            reset([{**monthly, 'id': 'refund', 'type': 'CANCELLATION', 'cancel_reason': 'CUSTOMER_SUPPORT',
                    'price': -10, 'price_in_purchased_currency': -9}])
            value = report()
            assert value['observed_gross_purchase_usd'] == 130 and value['refund_or_reversal_event_count'] == 1, value
            assert value['supported_observed_mrr_usd'] == 10 and value['net_revenue_usd'] is None, value

            for event_type in ['TRANSFER', 'FUTURE_EVENT']:
                reset([event('uncertain', type=event_type, original_transaction_id=None, transaction_id=None)])
                value = report()
                assert value['supported_observed_mrr_usd'] is None and value['unscoped_mrr_event_count'] == 1, value
                assert value['observed_gross_purchase_usd'] == 130, value

            reset([event('missing-environment', environment=None), event('missing-transaction', transaction_id=None),
                   event('family-sharing', is_family_share=True), event('unknown-product', product_id='unknown')])
            value = report()
            assert value['observed_gross_purchase_usd'] == 130 and value['supported_observed_mrr_usd'] == 20, value
            assert value['unclassified_environment_event_count'] == 1 and value['unkeyed_purchase_event_count'] == 1, value
            assert value['unsupported_charge_count'] == 2, value

            reset([event('missing-subscription-chain', original_transaction_id=None)])
            value = report()
            assert value['observed_gross_purchase_usd'] == 140 and value['supported_observed_mrr_usd'] == 20, value
            assert value['unkeyed_subscription_charge_count'] == 1, value

            invalid_currencies = ['ZZZ', 'XXX', 'XTS', 'XAU', 'XDR', 'BOV', 'XAD', 'BGN']
            reset([event('unsupported-' + code, currency=code) for code in invalid_currencies])
            value = report()
            assert value['observed_gross_purchase_usd'] == 130, 'Unsupported currencies entered gross: ' + str(value)
            assert value['observed_gross_by_currency'] == {'EUR': 9, 'USD': 120}, value
            assert value['supported_observed_mrr_usd'] == 20, 'Unsupported currencies polluted valid MRR: ' + str(value)
            assert value['unsupported_currency_charge_count'] == len(invalid_currencies), value
            assert value['unsupported_charge_count'] == len(invalid_currencies), value
            assert value['excluded_mrr_period_count'] == len(invalid_currencies), value
            assert sql('select count(*) from public.revenuecat_events;') == str(len(baseline) + len(invalid_currencies))

            reset([event('yen', currency='JPY', price_in_purchased_currency=1500),
                   event('dinar', currency='BHD', price_in_purchased_currency=3.769),
                   event('franc', currency='XAF', price_in_purchased_currency=5900),
                   event('unknown-beside-valid', currency='ZZZ')])
            value = report()
            assert value['observed_gross_purchase_usd'] == 160 and value['supported_observed_mrr_usd'] == 50, value
            assert value['observed_gross_by_currency'] == {'EUR': 9, 'USD': 120, 'JPY': 1500, 'BHD': 3.769, 'XAF': 5900}, value
            assert value['unsupported_currency_charge_count'] == 1, value

            reset([{**baseline[2], 'id': 'late-old-expiration', 'type': 'EXPIRATION',
                    'event_timestamp_ms': millis('2026-10-09T10:05:00Z')}])
            value = report()
            assert value['supported_observed_mrr_usd'] == 20, 'An old transaction expiry erased a newer paid period: ' + str(value)

            reset([{**monthly, 'id': 'refund-without-chain', 'type': 'CANCELLATION',
                    'original_transaction_id': None, 'cancel_reason': 'CUSTOMER_SUPPORT', 'price': -5}])
            value = report()
            assert value['supported_observed_mrr_usd'] == 10 and value['net_revenue_usd'] is None, value

            reset([{**monthly, 'id': 'unscoped-refund', 'type': 'CANCELLATION',
                    'original_transaction_id': None, 'transaction_id': None, 'cancel_reason': 'CUSTOMER_SUPPORT', 'price': -5}])
            value = report()
            assert value['supported_observed_mrr_usd'] is None and value['unscoped_mrr_event_count'] == 1, value

            reset([{**monthly, 'id': 'competing-period', 'transaction_id': 'another-paid-period'}])
            value = report()
            assert value['supported_observed_mrr_usd'] == 10 and value['excluded_mrr_period_count'] == 2, value

            reset()
            insert(event('future-api'), api_version='2.0')
            value = report()
            assert value['observed_gross_purchase_usd'] == 130 and value['supported_observed_mrr_usd'] is None, value
            assert value['unsupported_api_version_event_count'] == 1, value
            print('PASS: real PostgreSQL migration, immutable/concurrent event insertion, gross currency totals, replay/lifecycle dedupe, ordering, sandbox, refund exclusion, and conservative MRR scenarios.')
        finally:
            run(control + ['-m', 'fast', '-w', 'stop'])


if __name__ == '__main__':
    main()
