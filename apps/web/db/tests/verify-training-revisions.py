#!/usr/bin/env python3
"""Real transaction/concurrency checks in a disposable socket-only PostgreSQL.
Uses installed binaries, synthetic rows, and the actual migration. Never DATABASE_URL.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import getpass
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--postgres-bin', type=Path, required=True)
    parser.add_argument('--migration', type=Path, help='Optional candidate migration for deliberate regression checks')
    args = parser.parse_args()
    web = Path(__file__).resolve().parents[2]
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG') and k != 'DATABASE_URL'}
    env['PGCONNECT_TIMEOUT'] = '5'
    checks = []

    def run(command):
        result = subprocess.run(command, text=True, capture_output=True, env=env, timeout=30)
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout.strip()

    def quote(value):
        return "'" + str(value).replace("'", "''") + "'"

    with tempfile.TemporaryDirectory(prefix='lyb-revision-pg-',dir='/private/tmp') as directory:
        root = Path(directory)
        data, socket = root / 'data', root / 'socket'
        socket.mkdir(mode=0o700)
        run([str(args.postgres_bin / 'initdb'), '-D', str(data), '-A', 'trust', '--no-locale', '-U', getpass.getuser()])
        control = [str(args.postgres_bin / 'pg_ctl'), '-D', str(data)]
        run(control + ['-l', str(root / 'postgres.log'), '-o', f"-c listen_addresses='' -k {socket} -p 6548", '-w', 'start'])
        try:
            client = [str(args.postgres_bin / 'psql'), '-X', '-q', '-A', '-t', '-h', str(socket), '-p', '6548', '-U', getpass.getuser(), '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

            def sql(statement):
                return run(client + ['-c', statement])

            sql("create table schema_migrations(version text primary key); create table chat_usage_limits(user_subject text); create table chat_conversations(user_subject text); create table body_metrics(user_subject text);")
            for migration in ['20260714183000_create_app_users.sql','20260714213000_add_app_user_profile.sql',
                              '20260813130000_native_product_records.sql','20260927102000_training_record_collections.sql']:
                run(client + ['-f', str(web/'db/migrations'/migration)])
            run(client + ['-f', str(args.migration or web / 'db/migrations/20261010090000_training_revision_foundation.sql')])

            def owner():
                subject = 'synthetic-' + str(uuid.uuid4())
                sql(f"insert into app_users(id,identity_provider,identity_subject,profile_data) values('{uuid.uuid4()}','jovie',{quote(subject)},'{{\"date_of_birth\":\"1990-01-01\"}}');")
                return subject

            def context(subject):
                return json.loads(sql(f'select training_revision_context({quote(subject)});'))

            def command_sql(subject, action, body):
                return f'select training_revision_command({quote(subject)},{quote(action)},{quote(json.dumps(body))}::jsonb);'

            def command(subject, action, body):
                return json.loads(sql(command_sql(subject, action, body)))

            def new_proposal(subject):
                ctx = context(subject)
                proposal = dict(id=str(uuid.uuid4()), programId=str(uuid.uuid4()),
                    actor=dict(kind='self', subject=subject), createdAt='2026-10-10T12:00:00Z',
                    context={k: ctx[k] for k in ['generation','profileFingerprint','legacyFingerprint']})
                body = dict(requestId=str(uuid.uuid4()), requestHash='original-create-body', proposal=proposal)
                assert command(subject, 'create', body)['kind'] == 'stored'
                return body

            def decision(created, action='apply', request_id=None):
                proposal = created['proposal']
                revision = str(uuid.uuid4())
                return dict(requestId=request_id or str(uuid.uuid4()), proposalId=proposal['id'],
                    requestHash='body-' + action, now='2026-10-10T12:01:00Z', revisionId=revision,
                    setup=dict(id=proposal['programId'], programRevisionId=revision,
                        programPolicyVersion='hypertrophy-baseline-v1', consentVersion='hypertrophy-coach-v1',
                        adultConfirmed=True,safetyConfirmed=True,sessionsPerWeek=2,equipment='dumbbells',
                        startedAt='2026-10-10T12:01:00Z'))

            def counts(subject):
                return json.loads(sql(f'''select jsonb_build_array(
                  (select count(*) from training_revision_proposals where user_subject={quote(subject)}),
                  (select count(*) from training_program_revisions where user_subject={quote(subject)}),
                  (select count(*) from native_records where user_subject={quote(subject)} and deleted_at is null));'''))

            def check(name):
                checks.append(name)
                print('PASS ' + name, flush=True)

            def concurrent(*calls):
                with ThreadPoolExecutor(max_workers=len(calls)) as pool:
                    return list(pool.map(lambda fn: fn(), calls))

            def locked_order(subject, first_sql, second_sql):
                """Hold actual owner lock; observe the second backend blocked, then commit first.
                Polling observes pg_stat_activity lock state, not elapsed time as race evidence.
                """
                process = subprocess.Popen(client, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True, env=env, bufsize=1)
                process.stdin.write(f"begin; select id from app_users where identity_subject={quote(subject)} for update;\n\\echo OWNER_LOCKED\n")
                process.stdin.flush()
                while process.stdout.readline().strip() != 'OWNER_LOCKED':
                    if process.poll() is not None:
                        raise RuntimeError('lock holder failed')
                tag = 'training-wait-' + str(uuid.uuid4())
                with ThreadPoolExecutor(max_workers=1) as pool:
                    waiting = pool.submit(sql, f"set application_name={quote(tag)}; " + second_sql)
                    deadline = time.monotonic() + 10
                    while sql(f"select count(*) from pg_stat_activity where application_name={quote(tag)} and wait_event_type='Lock';") != '1':
                        if waiting.done() or time.monotonic() > deadline:
                            raise AssertionError('second transaction never blocked on owner lock')
                        time.sleep(0.01)
                    process.stdin.write(first_sql + '\ncommit;\n\\q\n')
                    process.stdin.flush()
                    process.stdin.close()
                    first_output = process.stdout.read()
                    error = process.stderr.read()
                    assert process.wait(timeout=10) == 0, error
                    second_output = waiting.result(timeout=10)
                return first_output, second_output

            subject = owner()
            assert context(subject)['generation'] == 0
            assert sql(f"select count(*) from training_revision_state where user_subject={quote(subject)};") == '0'
            check('pure context read creates no state')
            created = new_proposal(subject)
            same = concurrent(*[lambda: command(subject, 'create', created) for _ in range(4)])
            assert all(x['kind'] == 'stored' for x in same) and counts(subject) == [1,0,0]
            assert command(subject,'create',{**created,'requestHash':'changed'})['kind'] == 'request_conflict'
            apply = decision(created)
            results = concurrent(*[lambda: command(subject,'apply',apply) for _ in range(4)])
            assert all(x == results[0] and x['kind'] == 'decided' for x in results)
            assert counts(subject) == [1,1,1]
            assert command(subject,'apply',{**apply,'requestHash':'changed'})['kind'] == 'request_conflict'
            check('identical concurrent creates/applies replay one immutable receipt; changed key conflicts')

            subject = owner(); a = new_proposal(subject); b = new_proposal(subject)
            results = concurrent(lambda: command(subject,'apply',decision(a)),lambda: command(subject,'apply',decision(b)))
            assert sorted(x['kind'] for x in results) == ['decided','revision_conflict']
            assert counts(subject) == [2,1,1]
            check('competing proposals install exactly one revision/setup')

            subject=owner(); a=new_proposal(subject); b=new_proposal(subject); key=str(uuid.uuid4())
            assert command(subject,'apply',decision(a,request_id=key))['kind']=='decided'
            assert command(subject,'reject',decision(b,'reject',key))['kind']=='request_conflict'
            assert counts(subject)==[2,1,1]
            check('decision request identity cannot be reused for another proposal or decision')

            subject = owner(); a = new_proposal(subject)
            results = concurrent(lambda: command(subject,'apply',decision(a)),lambda: command(subject,'reject',decision(a,'reject')))
            assert sorted(x['kind'] for x in results) == ['already_decided','decided']
            winner = next(x['receipt'] for x in results if x['kind']=='decided')
            assert counts(subject)[1:] == ([1,1] if winner['status']=='applied' else [0,0])
            if winner['status']=='rejected': assert winner['setup'] is None and winner['revisionId'] is None
            check('apply/reject has one truthful terminal state')

            subject = owner(); a = new_proposal(subject); apply = decision(a)
            _, result = locked_order(subject,
                f"update app_users set profile_data='{{\"date_of_birth\":\"2020-01-01\"}}' where identity_subject={quote(subject)};",
                command_sql(subject,'apply',apply))
            assert json.loads(result)['kind']=='stale_context' and counts(subject)==[1,0,0]
            check('profile update lock winner invalidates previously reviewed canonical input')

            for first in ['revoke','apply']:
                subject=owner(); a=new_proposal(subject); apply=decision(a)
                first_sql=command_sql(subject,first,{} if first=='revoke' else apply)
                second_sql=command_sql(subject,'apply' if first=='revoke' else 'revoke',apply if first=='revoke' else {})
                _, result=locked_order(subject,first_sql,second_sql)
                assert json.loads(result)['kind'] == ('proposal_not_found' if first=='revoke' else 'revoked')
                assert counts(subject)==[0,0,0] and context(subject)['generation']==1
                assert command(subject,'create',a)['kind']=='stale_context'
                check(first+' first: consent removal dominates stale apply/create')

            for first in ['revoke','legacy_enroll']:
                subject=owner(); a=new_proposal(subject); setup=decision(a)['setup']
                setup.pop('programRevisionId'); setup.pop('programPolicyVersion')
                captured={'setup':setup,'context':a['proposal']['context']}
                _,result=locked_order(subject,
                    command_sql(subject,first,{} if first=='revoke' else captured),
                    command_sql(subject,'legacy_enroll' if first=='revoke' else 'revoke',captured if first=='revoke' else {}))
                assert json.loads(result)['kind']==('stale_context' if first=='revoke' else 'revoked'), {'first':first,'observed':json.loads(result),'counts':counts(subject)}
                assert counts(subject)==[0,0,0]
                check(first+' first: captured legacy enrollment cannot restore revoked consent')

            # Extract the exact existing-path cleanup statements, including owner lock.
            adapter=(web/'src/lib/neon/user-directory-adapter.ts').read_text().split('async deleteUser(subject)')[1]
            import re
            statements=re.findall(r'database`([^`]+)`',adapter)
            assert len(statements)==6 and 'for update' in statements[0]
            def deletion(subject):
                return ';'.join(s.replace('${subject}',quote(subject)) for s in statements)+';'
            for first in ['delete','apply']:
                subject=owner(); a=new_proposal(subject); apply=decision(a)
                _,result=locked_order(subject,deletion(subject) if first=='delete' else command_sql(subject,'apply',apply),
                    command_sql(subject,'apply',apply) if first=='delete' else 'begin;'+deletion(subject)+'commit;')
                if first=='delete': assert json.loads(result)['kind']=='owner_missing'
                assert counts(subject)==[0,0,0]
                assert sql(f"select count(*) from training_revision_state where user_subject={quote(subject)};")=='0'
                check(first+' first: account deletion leaves no recreated setup or ledger')

            subject=owner(); a=new_proposal(subject); apply=decision(a)
            sql("create function fail_training_insert() returns trigger language plpgsql as $$ begin raise exception 'injected setup failure'; end; $$; create trigger injected_failure before insert on native_records for each row execute function fail_training_insert();")
            try: command(subject,'apply',apply); raise AssertionError('expected setup failure')
            except RuntimeError as error: assert 'injected setup failure' in str(error)
            assert counts(subject)==[1,0,0] and context(subject)['headRevision'] is None
            assert sql(f"select status from training_revision_proposals where id='{a['proposal']['id']}';")=='proposed'
            sql('drop trigger injected_failure on native_records;')
            assert command(subject,'apply',apply)['kind']=='decided'
            check('second-write failure rolls back revision/head/receipt; same request safely retries')

            sql("create function fail_training_delete() returns trigger language plpgsql as $$ begin raise exception 'injected cleanup failure'; end; $$; create trigger injected_cleanup before delete on native_records for each row execute function fail_training_delete();")
            sql(f"insert into chat_usage_limits values({quote(subject)});")
            try: sql('begin;'+deletion(subject)+'commit;'); raise AssertionError('expected cleanup failure')
            except RuntimeError as error: assert 'injected cleanup failure' in str(error)
            assert counts(subject)==[1,1,1] and context(subject)['headRevision'] is not None
            assert sql(f"select count(*) from chat_usage_limits where user_subject={quote(subject)};")=='1'
            sql('drop trigger injected_cleanup on native_records;')
            check('account cleanup failure rolls back earlier cleanup and all original owner rows')

            other=owner()
            assert command(other,'apply',apply)['kind']=='proposal_not_found'
            assert sql(f"select coalesce(training_stored_proposal('{a['proposal']['id']}',{quote(other)})::text,'null');")=='null'
            # Direct owner-filtered read agrees with the production adapter predicates.
            assert sql(f"select count(*) from training_program_revisions where user_subject={quote(other)};")=='0'
            check('owner isolation prevents reading/deciding another proposal')
            export_source=(web/'src/lib/neon/training-revisions-adapter.ts').read_text().split('async exportForSubject(subject)')[1]
            export_queries=re.findall(r"'(select [^']+)'",export_source)
            assert len(export_queries)==2
            for query in export_queries:
                assert json.loads(sql(query.replace('$1',quote(subject))))
                assert sql(query.replace('$1',quote(other)))==''
            sql('begin;'+deletion(subject)+'commit;')
            for query in export_queries:
                assert sql(query.replace('$1',quote(subject)))==''
            assert context(other)['generation']==0
            check('exact adapter export queries are owner-scoped and empty after account cascade')

            subject=owner(); a=new_proposal(subject); legacy=decision(a)['setup']; legacy.pop('programRevisionId'); legacy.pop('programPolicyVersion')
            _, result=locked_order(subject,command_sql(subject,'legacy_enroll',{'setup':legacy,'context':a['proposal']['context']}),command_sql(subject,'apply',decision(a)))
            assert json.loads(result)['kind']=='stale_context' and counts(subject)==[1,0,1]
            # Existing no-head legacy enrollment remains replaceable, including old-consent state.
            legacy['consentVersion']='old-consent'; legacy['id']=str(uuid.uuid4())
            assert command(subject,'legacy_enroll',{'setup':legacy,'context':{k:v for k,v in context(subject).items() if k in ['generation','profileFingerprint','legacyFingerprint']}})['kind']=='enrolled'
            subject=owner(); a=new_proposal(subject)
            assert command(subject,'apply',decision(a))['kind']=='decided'
            assert command(subject,'legacy_enroll',{'setup':legacy,'context':{k:v for k,v in context(subject).items() if k in ['generation','profileFingerprint','legacyFingerprint']}})['kind']=='program_already_enrolled'
            check('legacy enrollment invalidates proposals; existing legacy replacement retained; canonical head cannot be bypassed')
            print(json.dumps({'passed':len(checks),'checks':checks,'scope':'disposable PostgreSQL16; synthetic rows; actual migration and extracted delete transaction'}))
        finally:
            run(control + ['-m','immediate','-w','stop'])


if __name__ == '__main__':
    main()
