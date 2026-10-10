# Reported measurements: server admission and preservation

This optional `dexa_results.reported_measurements` contract preserves reported
measurement kinds before native producers begin using them. It does not modify
historical rows, classify existing muscle scalars, or enable a native writer.
Existing `native_records.payload` JSONB storage needs no schema migration.

The stable envelope contains a positive safe-integer `schema_version` and an
`items` array. Each item has a nonempty `kind` of at most 80 characters. Limits
apply to every version: 16 KiB serialized UTF-8, 64 items/entries per container,
512 JSON nodes, depth 6 (root depth 0), and 160-character object keys. Non-JSON
values and non-finite numbers are rejected.

For version 1, recognized kinds are `lean_mass`, `fat_free_mass`, `muscle_mass`,
`skeletal_muscle_mass`, and `unidentified_mass`. Each requires a finite positive
`value`, a `unit` of `kg`, `lb`, `g`, or null, a nonblank `reported_label` of at
most 160 characters, and a nullable/nonblank `reported_unit` of at most 32
characters. Null means the unit is unidentified; it is not borrowed from weight.
The server performs no mass conversion, inference, or projection into
`muscle_mass`.

Unknown kinds and future versions are retained only as structurally bounded
JSON under the stable envelope. Acceptance does not validate their measurement
semantics. Consumers must not interpret them as mass without a separately
supported contract. Extra bounded fields are retained unchanged.

For DEXA records only:

- An absent field is valid for legacy clients. On update it preserves an existing
  field while all other payload keys retain their normal replacement behavior.
- A present, nonnull, valid envelope replaces the previous envelope, including
  an explicitly supplied empty `items` array.
- Explicit null or malformed/oversized data is rejected. The HTTP route rejects
  the whole batch before persistence; direct adapter calls reject each invalid
  record ID without writing it.
- The existing owner predicate remains mandatory. An update from another subject
  cannot alter the envelope or any other existing field.

Other collections retain their existing passthrough and replacement semantics,
including any unrelated field with the same name. Deploy this accepting and
preserving contract before a native producer; old clients can otherwise erase
unknown fields during decode, cache, and resync.

## Local PostgreSQL regression

Run the opt-in harness with PostgreSQL 16 or later installed:

```sh
python3 scripts/neon/test-reported-measurements.py --run --postgres-bin /path/to/postgresql/bin
```

Omit `--postgres-bin` if `initdb`, `pg_ctl`, and `psql` are on PATH. The harness
creates a disposable cluster with a private Unix socket and no TCP listener.
It does not read production credentials, DATABASE_URL, PG variables, or .env
files, and stops only its own cluster. It extracts and executes the actual
adapter upsert SQL against the existing native-records migration. Assertions
cover omission, explicit replacement (including an empty envelope), foreign
ownership, repeated legacy updates, and other collections. Missing JSON keys
fail the assertions; an absent value cannot pass as SQL NULL. No CI workflow
or production migration is changed.
