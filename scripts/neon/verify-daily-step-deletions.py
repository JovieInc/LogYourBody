#!/usr/bin/env python3
"""Replay actual daily adapter SQL and owner-lock schedules in disposable PG16 only."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DAY_START = "2026-03-08T08:00:00Z"
DAY_END = "2026-03-09T07:00:00Z"
ZONE = "America/Los_Angeles"


def quote(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def bind(statement, values):
    return re.sub(r"\$(\d+)", lambda match: quote(values[int(match[1]) - 1]), statement)


def one(pattern, source):
    matches = re.findall(pattern, source, re.S)
    if len(matches) != 1:
        raise AssertionError(f"Expected one actual SQL literal, found {len(matches)}: {pattern}")
    return matches[0]


def actual_queries(source_root, schema_root):
    adapter_path = source_root / "apps/web/src/lib/neon/native-product-records-adapter.ts"
    helper_path = schema_root / "apps/web/src/lib/neon/native-account-admission.ts"
    adapter, helper = adapter_path.read_text(), helper_path.read_text()
    daily = adapter.split("async function deleteDailySteps(", 1)[1].split(
        "async function endActiveGlp1Medications(", 1
    )[0]
    push = adapter.split("async function push(", 1)[1].split("\n  return {\n", 1)[0]
    queries = {
        "anchor": one(r"`(insert into public\.native_records .*?returning id, payload, deleted_at, updated_at)`", daily),
        "siblings": one(r"`(update public\.native_records target.*?returning target\.id, target\.payload, target\.deleted_at, target\.updated_at)`", daily),
        "push": one(r"`(insert into public\.native_records .*?returning id, payload, deleted_at, updated_at)`", push),
        "admit": one(r"database\.query\('(select public\.lyb_native_account_admit\(\$1, \$2::uuid\))'", helper),
    }
    assert "executeNativeMutationQueries(database, admission, queries)" in daily
    assert "executeNativeMutationQueries(database, admission, queries)" in push
    assert "database.transaction" in helper and "nativeAccountGuard(database, admission)" in helper
    return queries, {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in (adapter_path, helper_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--postgres-bin", required=True, type=Path)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--schema-root", type=Path, default=ROOT)
    args = parser.parse_args()
    if not args.run:
        parser.error("Pass --run to create an isolated socket-only cluster; no database is contacted by default")
    queries, bindings = actual_queries(args.source_root, args.schema_root)
    environment = {"PATH": os.defpath, "LC_ALL": "C", "PGCONNECT_TIMEOUT": "5"}

    def run(command, statement=None, check=True):
        result = subprocess.run(command, input=statement, text=True, capture_output=True,
                                timeout=30, env=environment)
        if check and result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result

    binaries = {}
    for name in ("initdb", "pg_ctl", "psql"):
        path = (args.postgres_bin / name).resolve()
        version = run([str(path), "--version"]).stdout.strip()
        if not re.search(r"\(PostgreSQL\) 16(?:\.|$)", version):
            raise RuntimeError("PostgreSQL16 required: " + version)
        binaries[name] = str(path)
    temporary = Path(tempfile.mkdtemp(prefix="lyb-daily-step-deletion-", dir="/private/tmp"))
    data, socket = temporary / "data", temporary / "socket"
    socket.mkdir(mode=0o700)
    ctl = [binaries["pg_ctl"], "-D", str(data)]
    results, waits = [], []
    try:
        run([binaries["initdb"], "-D", str(data), "-U", "daily_step_test",
             "--auth-local=trust", "--auth-host=reject", "--no-locale", "--encoding=UTF8"])
        run(ctl + ["-l", str(temporary / "server.log"), "-o",
                   f"-h '' -k {socket} -p 55491 -c shared_buffers=16MB -c max_connections=8 -c autovacuum=off",
                   "-w", "start"])
        client = [binaries["psql"], "-X", "-w", "-q", "-A", "-t", "-h", str(socket),
                  "-p", "55491", "-U", "daily_step_test", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]

        def sql(statement, check=True):
            return run(client, statement, check)

        sql("create table public.schema_migrations(version text primary key);")
        for name in ("20260714183000_create_app_users.sql", "20260813130000_native_product_records.sql",
                     "20261010120000_native_account_admission.sql"):
            path = args.schema_root / "apps/web/db/migrations" / name
            bindings[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
            run(client + ["-f", str(path)])

        def owner():
            subject, identity = "synthetic-" + str(uuid.uuid4()), str(uuid.uuid4())
            sql(f"insert into app_users(id,identity_subject)values({quote(identity)}::uuid,{quote(subject)});")
            return subject, identity

        def guard(subject, identity):
            return bind(queries["admit"], [subject, identity]) + ";"

        def transaction(subject, identity, statements):
            return "begin;" + guard(subject, identity) + statements + ";commit;"

        def record(record_id=None, **extra):
            return {"id": record_id or str(uuid.uuid4()), "date": "2026-03-08T18:00:00Z",
                    "steps": 8421, "steps_present": True, "notes": "saved note",
                    "future_field": {"nested": [1, "opaque"]}, **extra}

        def push(subject, value):
            # Match payloadForInsert; route/adapter tests separately prove its invocation.
            payload = {key: item for key, item in value.items()
                       if key not in ("user_id", "deleted_at", "server_updated_at", "steps_deletion")}
            return bind(queries["push"], ["daily_metrics", value["id"], subject, json.dumps(payload)])

        def delete(subject, value, start=DAY_START, end=DAY_END, zone=ZONE):
            payload = {key: item for key, item in value.items()
                       if key not in ("user_id", "deleted_at", "server_updated_at", "steps_deletion")}
            return bind(queries["anchor"], [value["id"], subject, json.dumps(payload), start, end, zone]) + ";" + bind(
                queries["siblings"], [value["id"], subject, start, end])

        def row(record_id):
            result = sql("select row_to_json(r) from native_records r where collection='daily_metrics' and id=" + quote(record_id) + ";").stdout.strip()
            return json.loads(result) if result else None

        def marked(record_id, expected):
            observed = row(record_id)
            assert observed is not None and observed["deleted_at"] is None
            payload = observed["payload"]
            assert payload["steps"] is None and payload["steps_present"] is False
            marker = payload["steps_deletion"]
            assert marker["schema_version"] == 1 and marker["day_start"] == DAY_START and marker["day_end"] == DAY_END
            assert marker["time_zone"] == ZONE and marker["deleted_at"]
            for key, value in expected.items():
                assert payload[key] == value, (key, payload[key], value)
            return observed

        def passed(name):
            results.append(name)
            print("PASS " + name, flush=True)

        @contextmanager
        def held_owner(subject, identity):
            holder = subprocess.Popen(client, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, env=environment, bufsize=1)
            try:
                holder.stdin.write("begin;\n\\o /dev/null\n" + guard(subject, identity)
                                   + "\n\\o\nselect 'OWNER_LOCKED:'||pg_backend_pid();\n")
                holder.stdin.flush()
                deadline = time.monotonic() + 10
                while True:
                    if not select.select([holder.stdout], [], [], max(0, deadline - time.monotonic()))[0]:
                        raise AssertionError("owner lock holder did not become ready")
                    line = holder.stdout.readline().strip()
                    if line.startswith("OWNER_LOCKED:"):
                        break
                    if holder.poll() is not None or time.monotonic() >= deadline:
                        raise AssertionError("owner lock holder exited before readiness")
                yield holder, int(line.split(":")[1])
            finally:
                if holder.poll() is None:
                    holder.stdin.write("rollback;\n\\q\n")
                    holder.stdin.flush()
                    holder.communicate(timeout=10)

        def race(subject, identity, first, second, label):
            with held_owner(subject, identity) as (holder, holder_pid):
                tag = "daily-delete-" + str(uuid.uuid4())
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future = pool.submit(sql, "set application_name=" + quote(tag) + ";" + transaction(subject, identity, second), False)
                    deadline = time.monotonic() + 10
                    while True:
                        observed = sql("select json_build_object('wait',wait_event_type,'blockers',pg_blocking_pids(pid)) from pg_stat_activity where application_name=" + quote(tag) + ";").stdout.strip()
                        value = json.loads(observed) if observed else None
                        if value and value["wait"] == "Lock" and holder_pid in value["blockers"]:
                            waits.append({"schedule": label, "waitEventType": "Lock", "actualHolderInBlockingPids": True})
                            break
                        if future.done() or time.monotonic() >= deadline:
                            raise AssertionError("second transaction did not wait on the held owner")
                        time.sleep(0.01)
                    holder.stdin.write(first + ";commit;\n\\q\n")
                    holder.stdin.flush()
                    output, error = holder.communicate(timeout=10)
                    assert holder.returncode == 0, error or output
                    result = future.result(timeout=10)
                    assert result.returncode == 0, result.stderr

        for deletion_first in (True, False):
            subject, identity = owner()
            anchor, incoming = record(notes="anchor note"), record(notes="import note", steps=0)
            assert anchor["id"] != incoming["id"]
            commands = (delete(subject, anchor), push(subject, incoming))
            label = "DELETE then different-ID POST" if deletion_first else "POST then different-ID DELETE"
            race(subject, identity, *(commands if deletion_first else commands[::-1]), label)
            for value in (anchor, incoming):
                marked(value["id"], {key: value[key] for key in ("id", "date", "notes", "future_field")})
            passed(label + " waits on actual account lock and retains unrelated fields")

        subject, identity = owner()
        anchor = record()
        sql(transaction(subject, identity, delete(subject, anchor)))
        original = marked(anchor["id"], {"notes": "saved note", "future_field": anchor["future_field"]})
        sql(transaction(subject, identity, push(subject, {"id": anchor["id"], "date": "2026-03-10T12:00:00Z", "steps": 99, "steps_present": True})))
        replayed = marked(anchor["id"], {"date": anchor["date"], "notes": "saved note", "future_field": anchor["future_field"]})
        assert replayed["payload"]["steps_deletion"] == original["payload"]["steps_deletion"]
        passed("same-ID stale replay cannot move or erase marker/date/notes/unknown JSON")
        for count in (0, 999):
            imported = record(steps=count)
            sql(transaction(subject, identity, push(subject, imported)))
            marked(imported["id"], {"notes": imported["notes"], "future_field": imported["future_field"]})
        passed("different-ID recorded zero and positive imports inherit the owner/day marker")
        sql(transaction(subject, identity, delete(subject, anchor, "2026-03-08T00:00:00-08:00", "2026-03-09T00:00:00-07:00")))
        assert row(anchor["id"])["payload"]["steps_deletion"] == original["payload"]["steps_deletion"]
        passed("repeat deletion accepts equivalent offset instants and retains original marker")

        next_day = record(date=DAY_END)
        sql(transaction(subject, identity, push(subject, next_day)))
        assert row(next_day["id"])["payload"]["steps"] == 8421
        passed("half-open end leaves the following day unchanged")
        foreign, foreign_identity = owner()
        own_foreign = record()
        sql(transaction(foreign, foreign_identity, push(foreign, own_foreign)))
        unchanged = row(anchor["id"])
        sql(transaction(foreign, foreign_identity, push(foreign, anchor)))
        sql(transaction(foreign, foreign_identity, delete(foreign, anchor)))
        assert row(anchor["id"]) == unchanged
        assert row(own_foreign["id"])["payload"]["steps"] == 8421
        passed("foreign-ID collision cannot change anchor or authorize another owner's day deletion")
        with held_owner(subject, identity):
            independent = record()
            sql(transaction(foreign, foreign_identity, push(foreign, independent)))
            assert row(independent["id"])["payload"]["steps"] == 8421
        passed("different owner completes while first owner's lock remains held")

        rollback_subject, rollback_owner = owner()
        rollback_row = record()
        failed = sql(transaction(rollback_subject, rollback_owner, delete(rollback_subject, rollback_row) + ";select 1/0"), False)
        assert failed.returncode != 0 and row(rollback_row["id"]) is None
        passed("later transaction failure rolls back marker and every daily write")
        sql("delete from app_users where id=" + quote(rollback_owner) + ";")
        replacement = str(uuid.uuid4())
        sql(f"insert into app_users(id,identity_subject)values({quote(replacement)}::uuid,{quote(rollback_subject)});")
        rejected = sql(transaction(rollback_subject, rollback_owner, delete(rollback_subject, rollback_row)), False)
        assert rejected.returncode != 0 and "account_changed" in rejected.stderr and row(rollback_row["id"]) is None
        passed("captured old account incarnation cannot create a deletion marker")
        print(json.dumps({"passed": len(results), "checks": results, "lockObservations": waits,
                          "sourceSha256": bindings, "liveDatabase": False}), flush=True)
    finally:
        if (data / "postmaster.pid").exists():
            run(ctl + ["-m", "fast", "-w", "stop"])
        shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
