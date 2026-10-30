"""Shared account-erasure SQL fixtures and vault transaction regression."""
import re
import uuid


def account_cleanup_statements(web, sql, load_migration):
    """Keep erasure fixtures current without stubbing newly deleted tables."""
    source = (web / 'src/lib/neon/user-directory-adapter.ts').read_text()
    adapter = source.split('async deleteUser(admission)')[1]
    statements = [re.sub(r'\s+', ' ', s).strip()
                  for s in re.findall(r'database`([^`]+)`', adapter)]
    required = [f'delete from public.{table} where user_subject = ${{subject}}'
                for table in ('chat_usage_limits', 'chat_conversations',
                              'weight_operation_receipts', 'body_metric_audit',
                              'metrics_agent_grants', 'body_metrics', 'native_records')]
    tail = ['select public.lyb_delete_my_gyms(${subject})',
            "delete from public.app_users where identity_provider = 'jovie' and identity_subject = ${subject}"]
    assert statements[:len(required)] == required and statements[-2:] == tail, 'preserve required account cleanup order and predicates'
    assert len(statements) == len(set(statements)), 'duplicate account cleanup'
    for statement in statements[len(required):-2]:
        match = re.fullmatch(r'delete from public\.([a-z_][a-z_0-9]*) where user_subject = \$\{subject\}', statement)
        assert match, f'expected exact subject-scoped cleanup: {statement}'
        table = match[1]
        exists = f"select to_regclass('public.{table}') is not null;"
        if sql(exists) == 't':
            continue
        # Resolve additions from canonical DDL, once per missing table, in both verifiers.
        migrations = [path for path in sorted((web / 'db/migrations').glob('*.sql'))
                      if re.search(rf'^create table if not exists public\.{table}\s*\(', path.read_text(), re.M | re.I)]
        assert len(migrations) == 1, f'expected unique migration defining {table}'
        load_migration(migrations[0])
        assert sql(exists) == 't', f'migration did not create {table}'
    return statements


def verify_vault_erasure(sql, owner, deletion, quote):
    def vault_counts(subject):
        return [int(sql(f'select count(*) from {table} where user_subject={quote(subject)};'))
                for table in ['health_vault_grants', 'health_vault_consent_log']]

    subject, other = owner(), owner()
    for vault_subject in [subject, other]:
        for kind in ['view', 'confirm', 'consent', 'media']:
            for expiry in ["now() - interval '1 hour'", "now() + interval '1 hour'"]:
                sql(f"insert into health_vault_grants(token_hash,user_subject,kind,expires_at,payload) values('{uuid.uuid4()}',{quote(vault_subject)},'{kind}',{expiry},'{{}}');")
        sql(f"insert into health_vault_consent_log(user_subject,consent_id,fields) values({quote(vault_subject)},'{uuid.uuid4()}','[\"weight\"]');")
    assert vault_counts(subject) == vault_counts(other) == [8, 1]
    sql(f"create function fail_vault_cleanup() returns trigger language plpgsql as $$ begin if old.identity_subject={quote(subject)} then raise exception 'injected vault cleanup failure'; end if; return old; end; $$; create trigger injected_vault_cleanup before delete on app_users for each row execute function fail_vault_cleanup();")
    try: sql('begin;'+deletion(subject)+'commit;'); raise AssertionError('expected vault cleanup failure')
    except RuntimeError as error: assert 'injected vault cleanup failure' in str(error)
    assert vault_counts(subject) == vault_counts(other) == [8, 1]
    assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};") == '1'
    sql('drop trigger injected_vault_cleanup on app_users;')
    sql('begin;'+deletion(subject)+'commit;')
    assert vault_counts(subject) == [0, 0] and vault_counts(other) == [8, 1]
    assert sql(f"select count(*) from app_users where identity_subject={quote(subject)};") == '0'
