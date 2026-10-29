#!/usr/bin/env python3
"""Training mutation consent/deletion transaction checks in a disposable socket-only PostgreSQL.
Uses installed binaries, synthetic rows, and the actual migration. Never DATABASE_URL.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import getpass
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def isolated_environment(environment):
    """Do not inherit a production endpoint, credential or connection option."""
    env = {key: value for key, value in environment.items()
           if not key.startswith('PG') and key != 'DATABASE_URL'}
    env['PGCONNECT_TIMEOUT'] = '5'
    return env


def run_command(command, env):
    result = subprocess.run(command, text=True, capture_output=True, env=env, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout or f'command failed: {Path(command[0]).name}')
    return result.stdout.strip()


def verify_postgres_tools(directory, env):
    """Fail closed before creating a cluster when CI's pinned substrate drifts."""
    versions = {}
    for name in ('initdb', 'pg_ctl', 'psql'):
        binary = directory / name
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError(f'missing executable PostgreSQL16 tool: {name}')
        version = run_command([str(binary), '--version'], env)
        if not re.search(r'\(PostgreSQL\) 16(?:\.|$)', version):
            raise RuntimeError(f'PostgreSQL16 required for {name}: {version}')
        versions[name] = version
    return versions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--postgres-bin', type=Path, required=True)
    parser.add_argument('--migration', type=Path, help='Optional candidate migration for deliberate regression checks')
    parser.add_argument('--admission-migration', type=Path, help='Optional admission migration for deliberate regression checks')
    parser.add_argument('--canvas-migration', type=Path, help='Optional canvas migration for deliberate regression checks')
    args = parser.parse_args()
    web = Path(__file__).resolve().parents[2]
    env = isolated_environment(os.environ)
    versions = verify_postgres_tools(args.postgres_bin, env)
    checks = []

    def run(command):
        return run_command(command, env)

    def quote(value):
        return "'" + str(value).replace("'", "''") + "'"

    with tempfile.TemporaryDirectory(prefix='lyb-mutation-pg-') as directory:
        root = Path(directory)
        data, socket = root / 'data', root / 'socket'
        socket.mkdir(mode=0o700)
        run([str(args.postgres_bin / 'initdb'), '-D', str(data), '-A', 'trust', '--no-locale', '-U', getpass.getuser()])
        control = [str(args.postgres_bin / 'pg_ctl'), '-D', str(data)]
        try:
            run(control + ['-l', str(root / 'postgres.log'), '-o', f"-c listen_addresses='' -k {socket} -p 6548", '-w', 'start'])
            client = [str(args.postgres_bin / 'psql'), '-X', '-q', '-A', '-t', '-h', str(socket), '-p', '6548', '-U', getpass.getuser(), '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

            def sql(statement):
                return run(client + ['-c', statement])

            sql("create table schema_migrations(version text primary key); create table chat_usage_limits(user_subject text); create table chat_conversations(user_subject text);")
            for migration in ['20260714183000_create_app_users.sql','20260714213000_add_app_user_profile.sql',
                              '20260715040000_create_body_metrics.sql','20260813120000_native_body_metrics_sync.sql',
                              '20261025120000_weight_lifecycle.sql','20261025190000_gym_registry.sql',
                              '20260813130000_native_product_records.sql','20260927102000_training_record_collections.sql']:
                run(client + ['-f', str(web/'db/migrations'/migration)])
            run(client + ['-f', str(args.migration or web / 'db/migrations/20261010090000_training_revision_foundation.sql')])

            run(client + ['-f', str(args.admission_migration or web / 'db/migrations/20261010103000_training_mutation_admission.sql')])

            run(client + ['-f', str(web / 'db/migrations/20261010120000_native_account_admission.sql')])
            run(client + ['-f', str(web / 'db/migrations/20261013100000_training_swap_mutation.sql')])
            run(client + ['-f', str(web / 'db/migrations/20261014103000_training_execution_cas.sql')])

            run(client + ['-f', str(args.canvas_migration or web / 'db/migrations/20261014180000_training_canvas_ledger.sql')])
            run(client + ['-f', str(web / 'db/migrations/20261025030000_adaptive_recovery_trials.sql')])

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

            def capture(subject, setup):
                ctx=context(subject)
                return dict(ownerId=ctx['ownerId'],generation=ctx['generation'],setupId=setup['id'],revisionId=setup.get('programRevisionId'))

            def enroll(subject, setup=None):
                setup=setup or dict(id=str(uuid.uuid4()),consentVersion='hypertrophy-coach-v1',
                    adultConfirmed=True,safetyConfirmed=True,sessionsPerWeek=2,equipment='dumbbells',startedAt='2026-01-01T00:00:00Z')
                ctx=context(subject)
                token={k:ctx[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}
                assert command(subject,'legacy_enroll',dict(setup=setup,context=token))['kind']=='enrolled'
                return setup

            def mutation_sql(subject, admission, action, record):
                if action == 'recovery_trial':
                    return recovery_sql(subject, admission, record)
                return f'select training_mutation_command({quote(subject)},{quote(action)},{quote(json.dumps(admission))}::jsonb,{quote(json.dumps(record))}::jsonb);'

            def recovery_basis(subject):
                return json.loads(sql(f"select coalesce(jsonb_object_agg(collection || '/' || id::text, payload || jsonb_build_object('id',id)), '{{}}'::jsonb) from native_records where user_subject={quote(subject)} and deleted_at is null and collection in ('training_sessions','logged_sets','training_feedback');"))

            def recovery_sql(subject, admission, record, revision=None, basis=None):
                expected = recovery_basis(subject) if basis is None else basis
                return f"select training_recovery_trial_command({quote(subject)},{quote(json.dumps(admission))}::jsonb,{quote(json.dumps(expected))}::jsonb,{'null' if revision is None else revision},{quote(json.dumps(record))}::jsonb);"

            def mutate(subject, admission, action, record):
                return json.loads(sql(mutation_sql(subject,admission,action,record)))

            def fixture():
                subject=owner(); setup=enroll(subject); admission=capture(subject,setup)
                session=dict(id=str(uuid.uuid4()),record_type='workout_session',programSetupId=setup['id'],status='in_progress',
                    prescription=dict(exercises=[dict(id='exercise',sets=2)]))
                assert mutate(subject,admission,'session_insert',session)['kind']=='saved'
                return subject,setup,admission,session

            def record_for(action, session):
                if action == 'recovery_trial':
                    return dict(id=str(uuid.uuid4()), record_type='recovery_trial', version=1, revision=0,
                        programSetupId=session['programSetupId'], programRevisionId=None, policyVersion='adaptive-recovery-v1',
                        blockId='block-1', exerciseId='exercise', state='proposed',
                        inference=dict(action='reduce', change=dict(kind='sets', to=1, **{'from': 2})),
                        history=[dict(revision=0, state='proposed')])
                if action in ['session_insert','session_update','completion']:
                    return dict(session,id=str(uuid.uuid4()) if action=='session_insert' else session['id'],
                        status='completed' if action=='completion' else 'in_progress')
                if action=='set_insert':
                    return dict(id=str(uuid.uuid4()),record_type='set_log',sessionId=session['id'],exerciseId='exercise',
                        setNumber=1,reps=10,loadKg=20,rir=2,completedAt='2026-01-01T00:00:00Z')
                if action=='swap_insert':
                    return dict(id=str(uuid.uuid4()),record_type='exercise_swap',programSetupId=session['programSetupId'],
                        blockId='block-1',sessionId=session['id'],fromExerciseId='exercise',toVariantId='variant')
                return dict(id=str(uuid.uuid4()),record_type='session_feedback',sessionId=session['id'],soreness=2,
                    pump=2,performance='stable',jointPain=0,createdAt='2026-01-01T00:00:00Z')

            def live_count(subject):
                return int(sql(f'select count(*) from native_records where user_subject={quote(subject)} and deleted_at is null;'))

            # Recovery source CAS and retained history use the real database function.
            subject, setup, admission, session = fixture()
            trial = record_for('recovery_trial', session)
            assert mutate(subject, admission, 'recovery_trial', trial)['kind'] == 'saved'
            proposed_basis = recovery_basis(subject)
            applied = dict(trial, revision=1, state='applied', appliedAt='2026-10-13T10:00:00Z',
                history=trial['history'] + [dict(revision=1, state='applied')])
            assert json.loads(sql(recovery_sql(subject, admission, applied, 0)))['kind'] == 'saved'
            # Stale source snapshots and stale decision revisions cannot overwrite the result.
            rejected = dict(applied, state='rejected')
            assert json.loads(sql(recovery_sql(subject, admission, rejected, 0, proposed_basis)))['kind'] == 'record_conflict'
            assert json.loads(sql(recovery_sql(subject, admission, rejected, 0)))['kind'] == 'record_conflict'
            reviewed = dict(applied, revision=2, outcome=dict(decision='inconclusive'),
                history=applied['history'] + [dict(revision=2, state='applied')])
            assert json.loads(sql(recovery_sql(subject, admission, dict(reviewed, inference={}), 1)))['kind'] == 'record_conflict'
            assert json.loads(sql(recovery_sql(subject, admission, dict(reviewed, history=[]), 1)))['kind'] == 'record_conflict'
            assert json.loads(sql(recovery_sql(subject, admission, reviewed, 1)))['kind'] == 'saved'
            other = record_for('recovery_trial', session)
            assert mutate(subject, admission, 'recovery_trial', other)['kind'] == 'saved'
            other_applied = dict(other, revision=1, state='applied', history=other['history'] + [dict(revision=1, state='applied')])
            assert json.loads(sql(recovery_sql(subject, admission, other_applied, 0)))['kind'] == 'record_conflict'
            reverted = dict(reviewed, revision=3, state='reverted', history=reviewed['history'] + [dict(revision=3, state='reverted')])
            assert json.loads(sql(recovery_sql(subject, admission, reverted, 2)))['kind'] == 'saved'
            assert json.loads(sql(recovery_sql(subject, admission, other_applied, 0)))['kind'] == 'saved'
            checks.append('recovery_source_cas_immutable_proposal_history_review_revert_single_active')

            import re
            adapter=(web/'src/lib/neon/user-directory-adapter.ts').read_text().split('async deleteUser(admission)')[1]
            statements=re.findall(r'database`([^`]+)`',adapter)
            expected_cleanup = [
                'delete from public.chat_usage_limits where user_subject = ${subject}',
                'delete from public.chat_conversations where user_subject = ${subject}',
                'delete from public.weight_operation_receipts where user_subject = ${subject}',
                'delete from public.body_metric_audit where user_subject = ${subject}',
                'delete from public.metrics_agent_grants where user_subject = ${subject}',
                'delete from public.body_metrics where user_subject = ${subject}',
                'delete from public.native_records where user_subject = ${subject}',
                'select public.lyb_delete_my_gyms(${subject})',
                "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ${subject}",
            ]
            assert [re.sub(r'\s+', ' ', s).strip() for s in statements] == expected_cleanup
            guard_source=(web/'src/lib/neon/native-account-admission.ts').read_text()
            guards=re.findall(r"database.query\('(select public.lyb_native_account_admit\(\$1, \$2::uuid\))'",guard_source)
            assert len(guards)==1, 'Expected the unique actual account guard SQL'
            def deletion(subject):
                # Capture before scheduling either transaction, never after its lock wait.
                owner_id=sql(f"select id from app_users where identity_provider='jovie' and identity_subject={quote(subject)};")
                assert owner_id
                guard=guards[0].replace('$1',quote(subject)).replace('$2',quote(owner_id))
                return guard+';'+ ';'.join(s.replace('${subject}',quote(subject)) for s in statements)+';'

            def gym_count(subject):
                return int(sql(f'select count(*) from gyms where user_subject={quote(subject)};'))

            subject,other=owner(),owner()
            for gym_subject in [subject,other]:
                # Account erasure must remove both active gyms and sync tombstones.
                for deleted_at in ['null', 'now()']:
                    sql(f"insert into gyms(id,user_subject,name,deleted_at) values('{uuid.uuid4()}',{quote(gym_subject)},'Synthetic gym',{deleted_at});")
            assert gym_count(subject)==gym_count(other)==2
            sql(f"create function fail_gym_account_cleanup() returns trigger language plpgsql as $$ begin if old.identity_subject={quote(subject)} then raise exception 'injected gym account cleanup failure'; end if; return old; end; $$; create trigger injected_gym_account_cleanup before delete on app_users for each row execute function fail_gym_account_cleanup();")
            try: sql('begin;'+deletion(subject)+'commit;'); raise AssertionError('expected gym cleanup failure')
            except RuntimeError as error: assert 'injected gym account cleanup failure' in str(error)
            assert gym_count(subject)==gym_count(other)==2
            assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};")=='1'
            sql('drop trigger injected_gym_account_cleanup on app_users;')
            sql('begin;'+deletion(subject)+'commit;')
            assert gym_count(subject)==0 and gym_count(other)==2
            assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};")=='0'
            check('gym account erasure rolls back on later failure, retries active and deleted rows, and preserves the other owner')

            def seed_weight(subject):
                owner_id=sql(f"select id from app_users where identity_subject={quote(subject)};")
                sql(f"insert into metrics_agent_grants(user_subject,owner_id,connected,consent_granted,entitled) values({quote(subject)},{quote(owner_id)},true,true,true);")
                body=dict(action='create', operation_id=str(uuid.uuid4()), record_id=str(uuid.uuid4()),
                    request_hash='synthetic-weight', now='2026-10-25T12:00:00Z', weight_kg='81.600000',
                    input_value='81.6', input_unit='kg', measured_at='2026-10-25T12:00:00Z',
                    utc_offset_minutes=0, local_date='2026-10-25', iana_zone='UTC', provenance={})
                result=json.loads(sql(f"select weight_lifecycle_command({quote(subject)},{quote(owner_id)},{quote(json.dumps(body))}::jsonb);"))
                assert result['outcome']=='committed'

            def weight_counts(subject):
                tables=['weight_operation_receipts','body_metric_audit','metrics_agent_grants','body_metrics']
                return [int(sql(f'select count(*) from {table} where user_subject={quote(subject)};')) for table in tables]

            subject,other=owner(),owner()
            seed_weight(subject); seed_weight(other)
            assert weight_counts(subject)==weight_counts(other)==[1,1,1,1]
            sql(f"create function fail_weight_cleanup() returns trigger language plpgsql as $$ begin if old.user_subject={quote(subject)} then raise exception 'injected weight cleanup failure'; end if; return old; end; $$; create trigger injected_weight_cleanup before delete on body_metrics for each row execute function fail_weight_cleanup();")
            try: sql('begin;'+deletion(subject)+'commit;'); raise AssertionError('expected weight cleanup failure')
            except RuntimeError as error: assert 'injected weight cleanup failure' in str(error)
            assert weight_counts(subject)==weight_counts(other)==[1,1,1,1]
            assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};")=='1'
            sql('drop trigger injected_weight_cleanup on body_metrics;')
            sql('begin;'+deletion(subject)+'commit;')
            assert weight_counts(subject)==[0,0,0,0] and weight_counts(other)==[1,1,1,1]
            assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};")=='0'
            check('weight account erasure rolls back on failure, retries completely, and preserves the other owner')

            for boundary in ['revoke','delete']:
                for action in ['session_insert','session_update','completion','set_insert','feedback_insert','swap_insert','set_correct','recovery_trial']:
                    for first in ['boundary','mutation']:
                        subject,setup,admission,session=fixture()
                        if action=='set_correct':
                            prior=record_for('set_insert', session)
                            assert mutate(subject,admission,'set_insert',prior)['kind']=='saved'
                            row=dict(prior, reps=9, revision=1, expectedRevision=0)
                        else:
                            row=record_for(action, session)
                        action_name='session_update' if action=='completion' else action
                        write=mutation_sql(subject,admission,action_name,row)
                        stop=command_sql(subject,'revoke',{}) if boundary=='revoke' else deletion(subject)
                        if first=='boundary':
                            _,result=locked_order(subject,stop,write)
                            assert json.loads(result)['kind']==('stale_admission' if boundary=='revoke' else 'owner_missing')
                        else:
                            result,_=locked_order(subject,write,'begin;'+stop+'commit;')
                            assert json.loads(result)['kind']=='saved'
                        assert live_count(subject)==0
                        check(f'{action}: {first} first vs {boundary} leaves zero live training rows')

            subject,setup,old,session=fixture(); row=record_for('set_insert',session)
            sql('begin;'+deletion(subject)+'commit;')
            # Exact production recordSignIn INSERT omits id; the DB creates a fresh UUID.
            sign_in_source=(web/'src/lib/neon/user-directory-adapter.ts').read_text().split('async recordSignIn(identity)')[1].split('async getUser')[0]
            assert 'insert into public.app_users' in sign_in_source and 'id,' not in sign_in_source.split(') values')[0]
            sql(f"insert into app_users(identity_provider,identity_subject,profile_data) values('jovie',{quote(subject)},'{{\"date_of_birth\":\"1990-01-01\"}}');")
            enroll(subject,setup); fresh=capture(subject,setup)
            assert fresh['generation']==old['generation'] and fresh['ownerId']!=old['ownerId']
            assert mutate(subject,fresh,'session_insert',session)['kind']=='saved'
            assert mutate(subject,old,'set_insert',row)['kind']=='stale_admission'
            assert mutate(subject,fresh,'set_insert',row)['kind']=='saved'
            check('delete/recreate same subject and matching generation/setup rejects old UUID; fresh request succeeds')

            subject,setup,admission,session=fixture()
            row=record_for('feedback_insert',session)
            for key in ['ownerId','generation','revisionId','setupId']:
                incomplete=dict(admission); incomplete.pop(key)
                assert mutate(subject,incomplete,'feedback_insert',row)['kind']=='stale_admission'
            assert mutate(subject,dict(admission,ownerId=None),'feedback_insert',row)['kind']=='stale_admission'
            assert live_count(subject)==2
            check('missing/null admission fields fail closed without SQL three-valued bypass')

            for action in ['apply','reject']:
                subject=owner(); created=new_proposal(subject); held=decision(created,action)
                sql('begin;'+deletion(subject)+'commit;')
                sql(f"insert into app_users(identity_provider,identity_subject,profile_data) values('jovie',{quote(subject)},'{{\"date_of_birth\":\"1990-01-01\"}}');")
                fresh=context(subject)
                replacement=dict(created,proposal=dict(created['proposal'],context={k:fresh[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}))
                assert command(subject,'create',replacement)['kind']=='stored'
                assert command(subject,action,held)['kind']=='stale_context'
                assert counts(subject)==[1,0,0]
                current=decision(replacement,action)
                missing=dict(current,context={k:v for k,v in current['context'].items() if k!='ownerId'})
                assert command(subject,action,missing)['kind']=='stale_context'
                assert command(subject,action,current)['kind']=='decided'
                assert command(subject,action,current)['kind']=='decided'
                check(f'held {action} cannot target recreated identical proposal; fresh decision and retry succeed')

            subject=owner(); created=new_proposal(subject); proposal_id=created['proposal']['id']
            sql(f"update training_revision_proposals set payload=jsonb_set(payload,'{{context}}',(payload->'context')-'ownerId') where id={quote(proposal_id)};")
            historical=json.loads(sql(f"select training_stored_proposal({quote(proposal_id)},{quote(subject)});"))
            assert 'ownerId' not in historical['proposal']['context']
            for action in ['apply','reject']:
                assert command(subject,action,decision(created,action))['kind']=='stale_context'
            assert counts(subject)==[1,0,0]
            check('historical proposal without incarnation remains readable and cannot authorize apply/reject')

            subject=owner(); old=context(subject); sql('begin;'+deletion(subject)+'commit;')
            sql(f"insert into app_users(identity_provider,identity_subject,profile_data) values('jovie',{quote(subject)},'{{\"date_of_birth\":\"1990-01-01\"}}');")
            fresh=context(subject)
            assert all(old[k]==fresh[k] for k in ['generation','profileFingerprint','legacyFingerprint'])
            setup=dict(id=str(uuid.uuid4()))
            token={k:old[k] for k in ['ownerId','generation','profileFingerprint','legacyFingerprint']}
            assert command(subject,'legacy_enroll',dict(setup=setup,context=token))['kind']=='stale_context'
            token.pop('ownerId')
            assert command(subject,'legacy_enroll',dict(setup=setup,context=token))['kind']=='stale_context'
            check('legacy enrollment cannot cross owner recreation or omit incarnation')

            subject,setup,admission,session=fixture(); row=record_for('set_insert',session)
            sql("create function fail_training_mutation() returns trigger language plpgsql as $$ begin if new.payload->>'record_type'='set_log' then raise exception 'injected mutation failure'; end if; return new; end; $$; create trigger injected_mutation before insert on native_records for each row execute function fail_training_mutation();")
            before=sql(f'select jsonb_agg(to_jsonb(n) order by id) from native_records n where user_subject={quote(subject)};')
            try: mutate(subject,admission,'set_insert',row); raise AssertionError('expected mutation failure')
            except RuntimeError as error: assert 'injected mutation failure' in str(error)
            assert sql(f'select jsonb_agg(to_jsonb(n) order by id) from native_records n where user_subject={quote(subject)};')==before
            sql('drop trigger injected_mutation on native_records;')
            assert mutate(subject,admission,'set_insert',row)['kind']=='saved'
            check('write failure rolls back without changing existing rows; same command retries')

            subject,setup,admission,session=fixture(); row=record_for('set_insert',session)
            outputs=concurrent(lambda:mutate(subject,admission,'set_insert',row),lambda:mutate(subject,admission,'set_insert',row))
            assert outputs[0]['record']==outputs[1]['record']
            changed=mutate(subject,admission,'set_insert',dict(row,reps=20))
            assert changed['record']['reps']==row['reps']
            assert changed['record']['server_updated_at']==outputs[0]['record']['server_updated_at']
            check('concurrent identical replay and changed payload return immutable accepted row for domain conflict check')
            # Already accepted set remains replayable after the effective volume shrinks.
            smaller=dict(session,prescription=dict(exercises=[dict(id='exercise',sets=1)]))
            row2=dict(row,id=str(uuid.uuid4()),setNumber=2)
            assert mutate(subject,admission,'set_insert',row2)['kind']=='saved'
            assert mutate(subject,admission,'session_update',smaller)['kind']=='saved'
            assert mutate(subject,admission,'set_insert',row2)['kind']=='saved'
            assert mutate(subject,admission,'set_insert',dict(row2,id=str(uuid.uuid4())))['kind']=='session_conflict'
            check('accepted replay precedes reduced-volume validation; new out-of-plan identity rejects')
            sql(f"update native_records set deleted_at=now() where collection='logged_sets' and id='{row['id']}';")
            assert mutate(subject,admission,'set_insert',row)['kind']=='record_conflict'
            check('set tombstone cannot be revived')

            other,other_setup,other_admission,other_session=fixture()
            other_before=sql(f'select jsonb_agg(to_jsonb(n) order by id) from native_records n where user_subject={quote(other)};')
            assert mutate(other,other_admission,'session_update',session)['kind']=='session_conflict'
            assert mutate(other,other_admission,'set_insert',dict(row2,sessionId=other_session['id']))['kind']=='record_conflict'
            assert sql(f'select jsonb_agg(to_jsonb(n) order by id) from native_records n where user_subject={quote(other)};')==other_before
            check('foreign session/global set identity cannot cross owners')
            subject,setup,admission,session=fixture()
            row=record_for('set_insert',session)
            assert mutate(subject,admission,'set_insert',row)['kind']=='saved'
            original=sql(f"select payload from native_records where collection='training_sessions' and id={quote(session['id'])};")
            optimized=dict(session,prescription=dict(exercises=session['prescription']['exercises'],executionRevision=1),
                expectedExecutionRevision=0,expectedLoggedSetCount=0)
            assert mutate(subject,admission,'session_update',optimized)['kind']=='record_conflict'
            assert sql(f"select payload from native_records where collection='training_sessions' and id={quote(session['id'])};")==original
            optimized['expectedLoggedSetCount']=1
            results=concurrent(lambda:mutate(subject,admission,'session_update',optimized),
                lambda:mutate(subject,admission,'session_update',optimized))
            assert sorted(result['kind'] for result in results)==['record_conflict','saved']
            saved=next(result['record'] for result in results if result['kind']=='saved')
            assert saved['prescription']['executionRevision']==1
            assert 'expectedExecutionRevision' not in saved and 'expectedLoggedSetCount' not in saved
            assert mutate(subject,admission,'session_update',optimized)['kind']=='record_conflict'
            completed=dict(optimized,status='completed',expectedExecutionRevision=1)
            assert mutate(subject,admission,'session_update',completed)['kind']=='saved'
            check('session CAS rejects stale logged count/revision, preserves rows, and admits one concurrent revision')

            subject,setup,admission,session=fixture(); row=record_for('set_insert',session)
            assert mutate(subject,admission,'set_insert',row)['kind']=='saved'
            corrected=dict(row,reps=12,revision=1,expectedRevision=0)
            competing=dict(corrected,reps=13)
            results=concurrent(lambda:mutate(subject,admission,'set_correct',corrected),
                lambda:mutate(subject,admission,'set_correct',competing))
            assert sorted(result['kind'] for result in results)==['record_conflict','saved']
            winner=next(result['record'] for result in results if result['kind']=='saved')
            assert winner['revision']==1 and winner['reps'] in (12,13)
            assert 'expectedRevision' not in winner
            before=sql(f"select payload from native_records where collection='logged_sets' and id={quote(row['id'])};")
            assert mutate(subject,admission,'set_correct',corrected)['kind']=='record_conflict'
            assert sql(f"select payload from native_records where collection='logged_sets' and id={quote(row['id'])};")==before
            fresh=dict(row,reps=14,revision=2,expectedRevision=1)
            assert mutate(subject,admission,'set_correct',fresh)['record']['reps']==14
            check('set correction admits one concurrent revision, rejects stale replay, and allows fresh correction')

            other,other_setup,other_admission,other_session=fixture()
            assert mutate(other,other_admission,'set_correct',dict(fresh,sessionId=other_session['id']))['kind']=='record_conflict'
            no_revision=dict(fresh); no_revision.pop('expectedRevision')
            assert mutate(subject,admission,'set_correct',no_revision)['kind']=='record_conflict'
            sql(f"update native_records set deleted_at=now() where collection='logged_sets' and id={quote(row['id'])};")
            assert mutate(subject,admission,'set_correct',dict(fresh,revision=3,expectedRevision=2))['kind']=='record_conflict'
            assert sql(f"select count(*) from native_records where collection='logged_sets' and id={quote(row['id'])} and deleted_at is null;")=='0'
            check('set correction cannot omit revision, cross owners, or revive a tombstone')

            canvas_env = {**env, 'TSX_TSCONFIG_PATH': str(web / 'tsconfig.json')}
            print(run_command(['node', '--conditions=react-server', '--import',
                str(web / 'node_modules/tsx/dist/loader.mjs'),
                str(web / 'db/tests/verify-training-canvas.ts'), json.dumps(client)], canvas_env), flush=True)
            check('canvas actual adapter/handler and SQL qualification')

            print(run_command(['node', '--conditions=react-server', '--import',
                str(web / 'node_modules/tsx/dist/loader.mjs'),
                str(web / 'db/tests/verify-training-recovery.ts'), json.dumps(client)], canvas_env), flush=True)
            check('recovery actual adapter/engine apply review revert and prescription replay')

            print(json.dumps({'passed':len(checks),'checks':checks,'postgresTools':versions,'scope':'disposable PostgreSQL16; actual migrations, observed owner locks, synthetic rows only'}))
        finally:
            run(control + ['-m','immediate','-w','stop'])

if __name__=='__main__':main()
