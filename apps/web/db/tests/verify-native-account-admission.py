#!/usr/bin/env python3
"""Actual adapter SQL and two-connection deletion schedules; disposable local PG only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid

WEB = Path(__file__).resolve().parents[2]
ROOT = WEB.parents[1]

def quote(value):
    if value is None:
        return 'null'
    return "'" + str(value).replace("'", "''") + "'"

def bind(statement, values):
    return re.sub(r'\$(\d+)', lambda m: quote(values[int(m[1])-1]), statement)

def one(pattern, source):
    values=re.findall(pattern, source, re.S)
    if len(values)!=1:
        raise AssertionError(f'Expected one actual SQL statement, got {len(values)}: {pattern}')
    return values[0]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--postgres-bin',type=Path,required=True)
    parser.add_argument('--baseline-root',type=Path,help='Original source snapshot for deliberate-red resurrection checks')
    args=parser.parse_args()
    source=(args.baseline_root or ROOT)/'apps/web/src/lib/neon'
    generic=(source/'native-product-records-adapter.ts').read_text()
    body=(source/'native-body-metrics-sync-adapter.ts').read_text()
    directory=(source/'user-directory-adapter.ts').read_text()
    upserts=re.findall(r'`(insert into public\.native_records .*?returning id, payload, deleted_at, updated_at)`',generic,re.S)
    upserts=[s for s in upserts if re.search(r'on conflict\s*\(collection,\s*id\)\s+do update set',s)]
    assert len(upserts)==1,'actual generic upsert must be unique'
    generic_push=upserts[0]
    body_push=one(r'`(insert into public\.body_metrics .*?returning \$\{columns\})`',body).replace('${columns}',one(r'const columns = `(.*?)`;',body))
    generic_remove=one(r'`(update public\.native_records\s+set deleted_at.*?returning id)`',generic)
    body_remove=one(r'`(update public\.body_metrics\s+set deleted_at.*?returning id)`',body)
    end_medication=one(r'`(update public\.native_records\s+set payload.*?returning id)`',generic)
    deletion=re.findall(r'database`(delete from public\..*?)`',directory,re.S)
    assert len(deletion)==5,'preserve complete actual account cleanup'
    guarded=not args.baseline_root
    if guarded:
        assert 'executeNativeMutationQueries(database, admission' in generic
        assert 'executeNativeMutationQueries(database, admission' in body
        assert 'executeNativeMutationQueries(database, admission' in directory
    helper=(WEB/'src/lib/neon/native-account-admission.ts').read_text()
    guard_query=one(r"database.query\('(select public.lyb_native_account_admit\(\$1, \$2::uuid\))'",helper)
    env={'PATH':os.defpath,'LC_ALL':'C','PGCONNECT_TIMEOUT':'5'}
    results=[]
    def run(command,input_text=None,check=True):
        r=subprocess.run(command,input=input_text,text=True,capture_output=True,env=env,timeout=30)
        if check and r.returncode: raise RuntimeError(r.stderr or r.stdout)
        return r
    with tempfile.TemporaryDirectory(prefix='lyb-native-admission-pg-',dir='/private/tmp') as temp:
        root=Path(temp);data=root/'data';socket=root/'socket';socket.mkdir(mode=0o700)
        run([str(args.postgres_bin/'initdb'),'-D',str(data),'-U',getpass.getuser(),'--auth-local=trust','--auth-host=reject','--no-locale','--encoding=UTF8'])
        ctl=[str(args.postgres_bin/'pg_ctl'),'-D',str(data)]
        run(ctl+['-l',str(root/'server.log'),'-o',f"-h '' -k {socket} -p 55489 -c shared_buffers=16MB -c max_connections=8 -c autovacuum=off",'-w','start'])
        try:
            client=[str(args.postgres_bin/'psql'),'-X','-q','-A','-t','-h',str(socket),'-p','55489','-U',getpass.getuser(),'-d','postgres','-v','ON_ERROR_STOP=1']
            def sql(statement,check=True):return run(client,input_text=statement,check=check)
            sql('create table schema_migrations(version text primary key); create table chat_usage_limits(user_subject text); create table chat_conversations(user_subject text);')
            for migration in ['20260714183000_create_app_users.sql','20260715040000_create_body_metrics.sql','20260813120000_native_body_metrics_sync.sql','20260813130000_native_product_records.sql','20261010120000_native_account_admission.sql']:
                run(client+['-f',str(WEB/'db/migrations'/migration)])
            def fixture():
                subject='synthetic-'+str(uuid.uuid4());owner=str(uuid.uuid4());rid=str(uuid.uuid4())
                sql(f"insert into app_users(id,identity_subject)values({quote(owner)}::uuid,{quote(subject)});")
                return subject,owner,rid
            def guard(s,o):return bind(guard_query,[s,o])+';'
            def delete(s,o):
                lock=guard(s,o) if guarded else f"select id from app_users where identity_subject={quote(s)} for update;"
                return 'begin;'+lock+';'.join(x.replace('${subject}',quote(s)) for x in deletion)+';commit;'
            def mutation(s,o,statement):return 'begin;'+(guard(s,o) if guarded else '')+statement+';commit;'
            def push(kind,s,rid,extra=None):
                if kind=='native_records':return bind(generic_push,['dexa_results',rid,s,json.dumps({'id':rid,**(extra or {})})])
                values=[rid,s,'2026-10-10','2026-10-10T10:00:00Z',80,'kg',19,'dexa',None,3,81,92,'cm','original note','https://example.com/photo','bodyspec_dexa',json.dumps({'vendor':'original'}),'2026-10-09T10:00:00Z','2026-10-10T10:00:00Z']
                if extra:values[5]=extra['weight_unit']
                return bind(body_push,values)
            def count(table,s):return int(sql(f'select count(*) from {table} where user_subject={quote(s)};').stdout.strip())
            def passed(name):results.append(name);print('PASS '+name,flush=True)
            red=[]
            for table in ['native_records','body_metrics']:
                s,o,r=fixture();sql(delete(s,o));result=sql(mutation(s,o,push(table,s,r)),False)
                if not guarded:
                    assert result.returncode==0 and count(table,s)==1
                    red.append(table);print('EXPECTED RED: original '+table+' upsert resurrected a row after DELETE',flush=True)
                else:
                    assert result.returncode!=0 and 'account_changed' in result.stderr and count(table,s)==0
                    passed(table+' delete-before-write rejects absent owner')
            if not guarded:
                print(json.dumps({'expectedFailures':red,'source':str(source)}));return 1
            # Observe a real row-lock wait; elapsed time is never the evidence.
            def locked_order(s,o,first,second):
                holder=subprocess.Popen(client,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env,bufsize=1)
                try:
                    holder.stdin.write('begin;'+guard(s,o)+'\n\\echo OWNER_LOCKED\n');holder.stdin.flush()
                    while holder.stdout.readline().strip()!='OWNER_LOCKED':
                        if holder.poll() is not None:raise AssertionError('holder failed')
                    tag='native-admission-'+str(uuid.uuid4())
                    with ThreadPoolExecutor(max_workers=1) as pool:
                        future=pool.submit(sql,f'set application_name={quote(tag)};'+second,False)
                        deadline=time.monotonic()+10
                        while sql(f"select count(*) from pg_stat_activity where application_name={quote(tag)} and wait_event_type='Lock';").stdout.strip()!='1':
                            if future.done() or time.monotonic()>deadline:raise AssertionError('second transaction did not block on owner')
                            time.sleep(.01)
                        holder.stdin.write(first+';commit;\n\\q\n');holder.stdin.flush();holder.stdin.close()
                        holder.stdout.read();error=holder.stderr.read();assert holder.wait(timeout=10)==0,error
                        return future.result(timeout=10)
                finally:
                    if holder.poll() is None:holder.terminate();holder.wait(timeout=5)
            for table in ['native_records','body_metrics']:
                s,o,r=fixture();after=locked_order(s,o,push(table,s,r),delete(s,o));assert after.returncode==0 and count(table,s)==0
                passed(table+' writer-before-delete waits then erases')
                s,o,r=fixture();cleanup=';'.join(x.replace('${subject}',quote(s)) for x in deletion)
                after=locked_order(s,o,cleanup,mutation(s,o,push(table,s,r)));assert after.returncode!=0 and 'account_changed' in after.stderr and count(table,s)==0
                passed(table+' delete-lock-before-writer rejects after wait')
                s,o,r=fixture();sql(delete(s,o));new=str(uuid.uuid4());sql(f'insert into app_users(id,identity_subject)values({quote(new)}::uuid,{quote(s)});')
                assert sql(mutation(s,o,push(table,s,r)),False).returncode!=0
                assert sql(delete(s,o),False).returncode!=0
                assert sql(f'select id from app_users where identity_subject={quote(s)};').stdout.strip()==new
                sql(mutation(s,new,push(table,s,r)));assert count(table,s)==1
                passed(table+' old capture cannot write/delete recreated owner; new capture works')
                # Same account existing records survive stale tombstones/completion.
                statements=[bind(body_remove,[s,'{'+r+'}'])] if table=='body_metrics' else [bind(generic_remove,[s,'dexa_results','{'+r+'}']),bind(end_medication,[s,'2026-10-10T11:00:00Z'])]
                for statement in statements:assert sql(mutation(s,o,statement),False).returncode!=0
                assert sql(f'select count(*) from {table} where user_subject={quote(s)} and deleted_at is not null;').stdout.strip()=='0'
                passed(table+' stale remove/end leave replacement rows unchanged')
                s,o,r=fixture();first=push(table,s,r);bad=push(table,s,str(uuid.uuid4()),{'weight_unit':'invalid'}) if table=='body_metrics' else bind(generic_push,['not_a_collection',str(uuid.uuid4()),s,'{}'])
                failed=sql(mutation(s,o,first+';'+bad),False);assert failed.returncode!=0 and count(table,s)==0
                passed(table+' later batch error rolls back all writes')
            s,o,r=fixture()
            for owner in [None,str(uuid.uuid4())]:assert sql(mutation(s,owner,push('native_records',s,r)),False).returncode!=0
            assert count('native_records',s)==0;passed('NULL or wrong UUID rejected by actual SQL')
            # Current-owner payload and foreign-ID behavior are identical to original SQL.
            envelope={'schema_version':9,'items':[{'future':{'large':9007199254740993}}]}
            sql(mutation(s,o,push('native_records',s,r,{'reported_measurements':envelope,'notes':'first'})))
            sql(mutation(s,o,push('native_records',s,r,{'notes':'legacy'})))
            payload=lambda:json.loads(sql(f'select payload from native_records where id={quote(r)};').stdout)
            assert payload()['reported_measurements']==envelope and payload()['notes']=='legacy'
            foreign,fo,fr=fixture();sql(mutation(foreign,fo,push('native_records',foreign,r,{'notes':'foreign'})));assert payload()['notes']=='legacy'
            sql(mutation(s,o,push('native_records',s,r,{'reported_measurements':{'schema_version':1,'items':[]}})));assert payload()['reported_measurements']['items']==[]
            passed('opaque omitted/explicit payload and foreign-ID rejection preserved')
            s,o,r=fixture();sql(mutation(s,o,push('body_metrics',s,r)));row=json.loads(sql(f'select row_to_json(b) from body_metrics b where id={quote(r)};').stdout)
            assert row['muscle_mass'] is None and row['notes']=='original note' and row['source_metadata']=={'vendor':'original'} and row['photo_url']=='https://example.com/photo'
            assert sql(f"select client_created_at = '2026-10-09T10:00:00Z'::timestamptz and client_updated_at = '2026-10-10T10:00:00Z'::timestamptz from body_metrics where id={quote(r)};").stdout.strip()=='t'
            foreign,fo,_=fixture();sql(mutation(foreign,fo,push('body_metrics',foreign,r)))
            assert count('body_metrics',foreign)==0
            assert json.loads(sql(f'select row_to_json(b) from body_metrics b where id={quote(r)};').stdout)==row
            passed('body nullable muscle/photo/source/client timestamps preserved')
            # Failure in actual delete rolls back all earlier deletes and the owner.
            sql("create function reject_test_delete()returns trigger language plpgsql as $$begin raise exception 'synthetic rollback';end$$; create trigger reject_test_delete before delete on native_records for each row execute function reject_test_delete();")
            sql(mutation(s,o,push('native_records',s,str(uuid.uuid4()))));failed=sql(delete(s,o),False);assert failed.returncode!=0 and count('body_metrics',s)==1 and count('native_records',s)==1
            assert sql(f'select count(*) from app_users where id={quote(o)};').stdout.strip()=='1';passed('actual deletion failure rolls back all rows and owner')
            print(json.dumps({'passed':len(results),'checks':results,'actualSQLSource':str(source),'liveDatabase':False}))
            return 0
        finally:
            run(ctl+['-m','fast','-w','stop'])

if __name__=='__main__':raise SystemExit(main())
