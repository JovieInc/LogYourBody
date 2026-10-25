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
    parser.add_argument('--cycle-migration', type=Path, help='Optional LYB-115 migration candidate')
    parser.add_argument('--migration', type=Path, help='Optional candidate migration for deliberate regression checks')
    parser.add_argument('--delegated-migration', type=Path, help='Optional delegated candidate for deliberate regression checks')
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

    with tempfile.TemporaryDirectory(prefix='lyb-revision-pg-') as directory:
        root = Path(directory)
        data, socket = root / 'data', root / 'socket'
        socket.mkdir(mode=0o700)
        run([str(args.postgres_bin / 'initdb'), '-D', str(data), '-A', 'trust', '--no-locale', '-U', getpass.getuser()])
        control = [str(args.postgres_bin / 'pg_ctl'), '-D', str(data)]
        try:
            run(control + ['-l', str(root / 'postgres.log'), '-o', f"-c listen_addresses='' -k {socket} -p 6548", '-w', 'start'])
        except RuntimeError:
            print((root / 'postgres.log').read_text())
            raise
        try:
            client = [str(args.postgres_bin / 'psql'), '-X', '-q', '-A', '-t', '-h', str(socket), '-p', '6548', '-U', getpass.getuser(), '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

            def sql(statement):
                return run(client + ['-c', statement])

            sql("create table schema_migrations(version text primary key); create table chat_usage_limits(user_subject text); create table chat_conversations(user_subject text); create table body_metrics(user_subject text);")
            for migration in ['20260714183000_create_app_users.sql','20260714213000_add_app_user_profile.sql',
                              '20260813130000_native_product_records.sql','20260927102000_training_record_collections.sql']:
                run(client + ['-f', str(web/'db/migrations'/migration)])
            run(client + ['-f', str(args.migration or web / 'db/migrations/20261010090000_training_revision_foundation.sql')])

            run(client + ['-f', str(web / 'db/migrations/20261010103000_training_mutation_admission.sql')])

            run(client + ['-f', str(web / 'db/migrations/20261010120000_native_account_admission.sql')])
            run(client + ['-f', str(web / 'db/migrations/20261014180000_training_canvas_ledger.sql')])
            run(client + ['-f', str(args.delegated_migration or web / 'db/migrations/20261025010000_delegated_training_revisions.sql')])
            run(client + ['-f', str(args.cycle_migration or web / 'db/migrations/20261025040000_training_cycle_lifecycle.sql')])
            run(client + ['-f', str(web / 'db/migrations/20261025190000_gym_registry.sql')])

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
                    context={k: ctx[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']})
                body = dict(requestId=str(uuid.uuid4()), requestHash='original-create-body', proposal=proposal)
                assert command(subject, 'create', body)['kind'] == 'stored'
                return body

            def decision(created, action='apply', request_id=None):
                proposal = created['proposal']
                revision = str(uuid.uuid4())
                return dict(requestId=request_id or str(uuid.uuid4()), proposalId=proposal['id'], context=proposal['context'],
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
            adapter=(web/'src/lib/neon/user-directory-adapter.ts').read_text().split('async deleteUser(admission)')[1]
            import re
            statements=re.findall(r'database`([^`]+)`',adapter)
            assert [' '.join(s.split()) for s in statements] == [
                'delete from public.chat_usage_limits where user_subject = ${subject}',
                'delete from public.chat_conversations where user_subject = ${subject}',
                'delete from public.body_metrics where user_subject = ${subject}',
                'delete from public.native_records where user_subject = ${subject}',
                'select public.lyb_delete_my_gyms(${subject})',
                "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ${subject}",
            ], 'Expected the complete ordered subject-scoped account cleanup'
            guard_source=(web/'src/lib/neon/native-account-admission.ts').read_text()
            guards=re.findall(r"database.query\('(select public.lyb_native_account_admit\(\$1, \$2::uuid\))'",guard_source)
            assert len(guards)==1, 'Expected the unique actual account guard SQL'
            def deletion(subject):
                # Capture before scheduling either transaction, never after its lock wait.
                owner_id=sql(f"select id from app_users where identity_provider='jovie' and identity_subject={quote(subject)};")
                assert owner_id
                guard=guards[0].replace('$1',quote(subject)).replace('$2',quote(owner_id))
                return guard+';'+ ';'.join(s.replace('${subject}',quote(subject)) for s in statements)+';'
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
            assert command(subject,'legacy_enroll',{'setup':legacy,'context':{k:v for k,v in context(subject).items() if k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}})['kind']=='enrolled'
            subject=owner(); a=new_proposal(subject)
            assert command(subject,'apply',decision(a))['kind']=='decided'
            assert command(subject,'legacy_enroll',{'setup':legacy,'context':{k:v for k,v in context(subject).items() if k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}})['kind']=='program_already_enrolled'
            check('legacy enrollment invalidates proposals; existing legacy replacement retained; canonical head cannot be bypassed')
            # Cycle revisions share exactly the same owner lock, head CAS and receipt ledger.
            subject=owner(); initial=new_proposal(subject); initial_apply=decision(initial)
            assert command(subject,'apply',initial_apply)['kind']=='decided'
            program=initial_apply['setup']['id']

            def cycle_proposal(repeat=False):
                ctx=context(subject)
                prior=json.loads(sql(f"select payload - 'record_type' from native_records where user_subject={quote(subject)} and collection='training_feedback' and id='{program}';"))
                proposed=dict(prior)
                proposed['cycle']=dict(weekCount=5,temporaryPriorities=[],temporaryConstraints=[],retainedVariants=[],historyProgramIds=[program] if repeat else [])
                proposed['id']=str(uuid.uuid4()) if repeat else program
                proposal=dict(id=str(uuid.uuid4()),programId=proposed['id'],baseRevision=ctx['headRevision'],
                    context={k:ctx[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']},
                    actor=dict(kind='self',subject=subject),createdAt='2026-10-25T12:00:00Z',
                    intent=dict(kind='repeat_cycle' if repeat else 'revise_cycle',weekCount=5),
                    priorState=dict(setup=prior,trainingFingerprint=ctx['trainingFingerprint']),proposedSetup=proposed)
                body=dict(requestId=str(uuid.uuid4()),requestHash='cycle-'+proposal['id'],proposal=proposal)
                assert command(subject,'create',body)['kind']=='stored'
                apply=decision(body); apply['setup']=dict(proposed,programRevisionId=apply['revisionId'])
                return body,apply

            stale,stale_apply=cycle_proposal()
            session=str(uuid.uuid4()); prescription=dict(id=session,week=1,exercises=[dict(id='goblet_squat',sets=2)])
            session_payload=dict(record_type='workout_session',programSetupId=program,
                programRevisionId=initial_apply['revisionId'],status='in_progress',prescription=prescription)
            sql(f"insert into native_records(collection,id,user_subject,payload) values('training_sessions','{session}',{quote(subject)},{quote(json.dumps(session_payload))}::jsonb);")
            assert command(subject,'apply',stale_apply)['kind']=='stale_context'
            check('new session invalidates an already reviewed cycle draft under the owner lock')

            first,first_apply=cycle_proposal(); competing,competing_apply=cycle_proposal()
            assert command(subject,'apply',first_apply)['kind']=='decided'
            assert command(subject,'apply',first_apply)['receipt']['revisionId']==first_apply['revisionId']
            assert command(subject,'apply',competing_apply)['kind']=='revision_conflict'
            saved=json.loads(sql(f"select payload from native_records where id='{session}' and collection='training_sessions';"))
            assert saved['prescription']==prescription and saved['status']=='in_progress'
            assert saved['programRevisionId']==first_apply['revisionId']
            assert context(subject)['headRevision']==first_apply['revisionId']
            check('length revision preserves unfinished prescription, atomically rebinds authority, and excludes competing applies')

            sql(f"update native_records set payload=jsonb_set(payload,'{{status}}','\"ended\"'::jsonb) where id='{session}';")
            repeated,repeat_apply=cycle_proposal(True)
            assert command(subject,'apply',repeat_apply)['kind']=='decided'
            assert sql(f"select count(*) from native_records where user_subject={quote(subject)} and collection='training_feedback' and deleted_at is null;")=='1'
            assert json.loads(sql(f"select payload->'prescription' from native_records where id='{session}';"))==prescription
            assert sql(f"select count(*) from training_program_revisions where user_subject={quote(subject)};")=='3'
            check('next-block revision preserves session and revision history while leaving one current setup')
            def delegated_proposal(subject, changes=None):
                ctx=context(subject)
                current=sql(f"select payload - 'record_type' from native_records where user_subject={quote(subject)} and collection='training_feedback' and deleted_at is null and coalesce(payload->>'programRevisionId','')={quote(ctx['headRevision'] or '')} order by payload->>'startedAt' desc limit 1;")
                prior=json.loads(current) if current else None
                program=dict(prior['delegated']) if prior and 'delegated' in prior else dict(inputs=dict(sessionsPerWeek=prior['sessionsPerWeek'] if prior else 2,equipment=prior['equipment'] if prior else 'dumbbells'),authority=dict(trainerSubject=None,coachDelegated=False))
                if changes: program.update(changes)
                proposal=dict(version=2,id=str(uuid.uuid4()),programId=prior['id'] if prior else str(uuid.uuid4()),
                    ownerSubject=subject,baseRevision=ctx['headRevision'],context={k:ctx[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']},
                    actor=dict(kind='coach',subject='lyb-coach'),authority='user_review',priorState=prior,
                    proposedState=program,policyVersion='delegated-canvas-v1',createdAt='2026-10-25T12:00:00Z',
                    inputEvidence=dict(fingerprint=sql(f'select training_planning_fingerprint({quote(subject)});')))
                body=dict(requestId=str(uuid.uuid4()),requestHash=str(uuid.uuid4()),proposal=proposal)
                assert command(subject,'create',body)['kind']=='stored'
                return body

            def delegated_decision(created, actor=None):
                result=decision(created)
                p=created['proposal']
                result['actor']=actor or dict(kind='user',subject=p['ownerSubject'])
                result['evidenceFingerprint']=p['inputEvidence']['fingerprint']
                result['setup'].update(delegated=p['proposedState'],programPolicyVersion='delegated-canvas-v1',
                    sessionsPerWeek=p['proposedState']['inputs']['sessionsPerWeek'],equipment=p['proposedState']['inputs']['equipment'])
                return result

            subject=owner(); initial_legacy=new_proposal(subject); setup=decision(initial_legacy)['setup']
            setup.pop('programRevisionId'); setup.pop('programPolicyVersion')
            assert command(subject,'legacy_enroll',dict(setup=setup,context=initial_legacy['proposal']['context']))['kind']=='enrolled'
            replacement=dict(setup,id=str(uuid.uuid4()),startedAt='2026-10-12T12:00:00Z')
            captured={k:context(subject)[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}
            assert command(subject,'legacy_enroll',dict(setup=replacement,context=captured))['kind']=='enrolled'
            adopted=delegated_proposal(subject)
            assert adopted['proposal']['priorState']==replacement
            assert command(subject,'apply',delegated_decision(adopted))['kind']=='decided'
            assert counts(subject)==[2,1,2]
            check('legacy baseline adoption reuses one setup and retains exact prior state')

            subject=owner(); initial=delegated_proposal(subject); accepted=delegated_decision(initial)
            result=command(subject,'apply',accepted)
            assert result['kind']=='decided' and result['receipt']['version']==2 and context(subject)['generation']==1
            assert command(subject,'apply',accepted)==result
            check('delegated initial enrollment atomically commits setup/head/immutable receipt and replays')
            legacy_canvas=json.loads(sql(f"select training_canvas_save({quote(subject)},{quote(context(subject)['ownerId'])}::uuid,null,{quote(json.dumps(dict(version=1,write=1,generation=0)))}::jsonb);"))
            assert legacy_canvas['kind']=='canonical_revision_required'
            assert sql(f"select count(*) from training_canvas_ledgers where user_subject={quote(subject)};")=='0'
            check('older canvas clients cannot install a second plan after delegated acceptance')


            a=delegated_proposal(subject,dict(inputs=dict(sessionsPerWeek=4,equipment='dumbbells')))
            b=delegated_proposal(subject,dict(inputs=dict(sessionsPerWeek=3,equipment='dumbbells')))
            first,second=locked_order(subject,command_sql(subject,'apply',delegated_decision(a)),command_sql(subject,'apply',delegated_decision(b)))
            assert 'decided' in first and json.loads(second)['kind']=='stale_context'
            assert counts(subject)==[3,2,1]
            check('delegated concurrent edits keep one canonical setup and admit only one new revision')

            stale=delegated_proposal(subject)
            sql(f"insert into native_records(collection,id,user_subject,payload,updated_at) values('training_feedback','{uuid.uuid4()}',{quote(subject)},{quote(json.dumps(dict(record_type='session_feedback')))},now());")
            assert command(subject,'apply',delegated_decision(stale))['kind']=='stale_context'
            check('new recovery evidence invalidates a delegated draft inside the owner lock')

            active=str(uuid.uuid4())
            sql(f"insert into native_records(collection,id,user_subject,payload,updated_at) values('training_sessions','{active}',{quote(subject)},{quote(json.dumps(dict(record_type='workout_session',status='in_progress',programSetupId=initial['proposal']['programId'])))},now());")
            delayed=delegated_proposal(subject)
            delayed_request=delegated_decision(delayed)
            assert command(subject,'apply',delayed_request)['kind']=='delayed_active_workout'
            assert command(subject,'apply',delayed_request)['kind']=='delayed_active_workout'
            stored=json.loads(sql(f"select training_stored_proposal('{delayed['proposal']['id']}',{quote(subject)});"))
            assert stored['status']=='proposed' and len(stored['attempts'])==1
            assert stored['attempts'][0]['reason']=='active_workout' and stored['attempts'][0]['actor']==delayed_request['actor']
            sql(f"update native_records set deleted_at=now() where id='{active}';")
            check('active workout delays delegated application without a false applied receipt')

            grant=delegated_proposal(subject,dict(authority=dict(trainerSubject='authorized-trainer',coachDelegated=False)))
            assert command(subject,'apply',delegated_decision(grant))['kind']=='decided'
            trained=delegated_proposal(subject)
            assert command(subject,'apply',delegated_decision(trained,dict(kind='trainer',subject='stranger')))['kind']=='unauthorized_actor'
            trainer=delegated_decision(trained,dict(kind='trainer',subject='authorized-trainer'))
            assert command(subject,'apply',trainer)['receipt']['actor']==trainer['actor']
            check('only the currently authorized trainer can commit and its actor is retained')

            rollback=delegated_proposal(subject); before=counts(subject); head=context(subject)['headRevision']
            sql("create trigger injected_edit_failure before update on native_records for each row execute function fail_training_insert();")
            try: command(subject,'apply',delegated_decision(rollback)); raise AssertionError('expected delegated setup failure')
            except RuntimeError as error: assert 'injected setup failure' in str(error)
            assert counts(subject)==before and context(subject)['headRevision']==head
            assert sql(f"select status from training_revision_proposals where id='{rollback['proposal']['id']}';")=='proposed'
            sql('drop trigger injected_edit_failure on native_records;')
            check('delegated setup update failure rolls back the new revision/head/receipt')

            print(json.dumps({'passed':len(checks),'checks':checks,'scope':'disposable PostgreSQL16; synthetic rows; actual migration and extracted delete transaction'}))
        finally:
            run(control + ['-m','immediate','-w','stop'])


if __name__ == '__main__':
    main()
