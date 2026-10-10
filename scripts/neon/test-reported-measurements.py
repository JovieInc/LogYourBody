#!/usr/bin/env python3
"""Opt-in regression using the adapter's SQL in a disposable, socket-only cluster."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPO_ROOT = Path(__file__).resolve().parents[2]
ADAPTER = REPO_ROOT / "apps/web/src/lib/neon/native-product-records-adapter.ts"
MIGRATION = REPO_ROOT / "apps/web/db/migrations/20260813130000_native_product_records.sql"
OWNER_ID = "11111111-1111-4111-8111-111111111111"
LEGACY_ID = "22222222-2222-4222-8222-222222222222"
ENVELOPE = {
    "schema_version": 1,
    "items": [{"kind": "lean_mass", "value": 62, "unit": "kg",
               "reported_label": "Lean Mass", "reported_unit": "kg"}],
}
FUTURE = {"schema_version": 2, "items": [{"kind": "future", "value": {"raw": True}}]}


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def document(value):
    return literal(json.dumps(value, separators=(",", ":"))) + "::jsonb"


def write(collection, owner, payload):
    values = [collection, payload["id"], owner, json.dumps(payload)]
    return "EXECUTE write_record(" + ",".join(map(literal, values)) + ");"


def check(condition, message):
    # Missing JSON keys produce SQL NULL, which must fail rather than pass.
    return ("DO $$ BEGIN IF (" + condition + ") IS NOT TRUE THEN RAISE EXCEPTION "
            + literal(message) + "; END IF; END $$;")


def regression_sql():
    statements = re.findall(
        r"`(insert into public\.native_records .*?returning id, payload, deleted_at, updated_at)`",
        ADAPTER.read_text(), re.S,
    )
    if len(statements) != 1:
        raise RuntimeError("Expected one actual native-records upsert in the adapter")
    lookup = ("(SELECT payload FROM public.native_records WHERE collection='dexa_results' "
              "AND id=" + literal(OWNER_ID) + ")")
    sql = ["PREPARE write_record(text,uuid,text,text) AS " + statements[0] + ";"]
    sql += [
        write("dexa_results", "owner-a", {"id": OWNER_ID, "reported_measurements": ENVELOPE,
                                           "obsolete": "replace me"}),
        write("dexa_results", "owner-a", {"id": OWNER_ID, "notes": "legacy update"}),
        check(lookup + "->'reported_measurements' = " + document(ENVELOPE),
              "legacy omission erased reported measurements"),
        check(lookup + "->>'notes' = 'legacy update' AND NOT (" + lookup + " ? 'obsolete')",
              "unrelated fields did not retain replacement semantics"),
        write("dexa_results", "owner-b", {"id": OWNER_ID, "reported_measurements": FUTURE,
                                           "notes": "foreign overwrite"}),
        check(lookup + "->'reported_measurements' = " + document(ENVELOPE)
              + " AND " + lookup + "->>'notes' = 'legacy update'",
              "foreign owner altered the record"),
        write("dexa_results", "owner-a", {"id": OWNER_ID, "reported_measurements": FUTURE}),
        check(lookup + "->'reported_measurements' = " + document(FUTURE),
              "explicit future envelope was not retained raw"),
        write("dexa_results", "owner-a", {"id": OWNER_ID, "notes": "legacy again"}),
        write("dexa_results", "owner-a", {"id": OWNER_ID, "notes": "legacy again"}),
        check(lookup + "->'reported_measurements' = " + document(FUTURE),
              "repeated legacy update erased the future envelope"),
        write("dexa_results", "owner-a", {"id": OWNER_ID, "reported_measurements": {
            "schema_version": 1, "items": []}}),
        check(lookup + "->'reported_measurements' = " + document({"schema_version": 1, "items": []}),
              "explicit empty envelope did not replace measurements"),
        write("daily_metrics", "owner-a", {"id": OWNER_ID, "reported_measurements": ENVELOPE}),
        write("daily_metrics", "owner-a", {"id": OWNER_ID, "steps": 123}),
        check("NOT ((SELECT payload FROM public.native_records WHERE collection='daily_metrics' "
              "AND id=" + literal(OWNER_ID) + ") ? 'reported_measurements')",
              "other collection replacement behavior changed"),
        write("dexa_results", "owner-b", {"id": LEGACY_ID, "notes": "legacy insert"}),
        check("NOT ((SELECT payload FROM public.native_records WHERE collection='dexa_results' "
              "AND id=" + literal(LEGACY_ID) + ") ? 'reported_measurements')",
              "legacy insert invented measurements"),
    ]
    return "\n".join(sql) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="create a disposable local PostgreSQL cluster")
    parser.add_argument("--postgres-bin", type=Path, help="directory containing PostgreSQL 16+ binaries")
    args = parser.parse_args()
    if not args.run:
        parser.error("Pass --run to opt in; no database is contacted by default")
    binaries = {}
    for name in ("initdb", "pg_ctl", "psql"):
        candidate = args.postgres_bin / name if args.postgres_bin else shutil.which(name)
        if not candidate or not Path(candidate).is_file():
            parser.error("PostgreSQL binaries not found; pass --postgres-bin")
        binaries[name] = str(Path(candidate).resolve())
    sql = regression_sql()
    # No DATABASE_URL, PG*, .env, or user connection configuration is inherited.
    environment = {"PATH": os.defpath, "LC_ALL": "C"}
    temporary = Path(tempfile.mkdtemp(prefix="lyb-measurements-", dir="/tmp"))
    cluster = temporary / "data"
    socket = temporary / "socket"
    socket.mkdir(mode=0o700)

    def run(command, input_text=None):
        return subprocess.run(command, input=input_text, text=True, env=environment,
                              check=True, timeout=60, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT).stdout

    try:
        run([binaries["initdb"], "-D", str(cluster), "-U", "measurement_test",
             "--auth-local=trust", "--auth-host=reject", "--no-locale", "--encoding=UTF8"])
        run([binaries["pg_ctl"], "-D", str(cluster), "-l", str(temporary / "server.log"),
             "-o", f"-k {socket} -p 55484 -h '' -c shared_buffers=16MB -c max_connections=5 -c autovacuum=off",
             "-w", "start"])
        psql = [binaries["psql"], "-X", "-w", "-v", "ON_ERROR_STOP=1", "-h", str(socket),
                "-p", "55484", "-U", "measurement_test", "-d", "postgres"]
        run([*psql, "-c", "CREATE TABLE public.schema_migrations(version text PRIMARY KEY);"])
        run([*psql, "-f", str(MIGRATION)])
        run(psql, sql)
        print("PASS: actual adapter SQL preserves measurements, ownership and legacy compatibility")
    except subprocess.CalledProcessError as error:
        print(error.stdout or "PostgreSQL command failed")
        raise SystemExit(1) from error
    finally:
        # Only this newly created cluster is stopped; retain it if stopping fails.
        if (cluster / "postmaster.pid").exists():
            try:
                run([binaries["pg_ctl"], "-D", str(cluster), "-m", "fast", "-w", "stop"])
            except (subprocess.SubprocessError, OSError):
                print(f"Could not stop task-owned cluster; retained at {temporary}")
                raise
        shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
