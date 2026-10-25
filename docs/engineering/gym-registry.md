# Gym registry (LYB-248)

The native Ask surface exposes **Your gyms** when the default-off Statsig gate
`gym_registry_v1` is enabled. The first-party `/api/auth/mobile/gyms/v1` API also
requires `LYB_GYM_REGISTRY_ENABLED=true`. Register, edit, delete and manually
select gyms there. Adding or syncing a gym never selects it. Nothing requests
location access, infers inventory, or seeds equipment from a gym name or region.

The active choice is local to the account and device and survives launches.
**No gym selected** passes no equipment filter; all catalog equipment is allowed
for browsing without asserting availability. A selected gym passes its exact
confirmed set, including an empty set. Preferred machine names are user-entered
notes and never imply availability. Browse filtering does not change existing
engine prescriptions or enroll a training program.

Core Data V5 adds an account-scoped journal with gym values, pending mutation
IDs, delete tombstones and the active choice. Local saves happen before sync;
failed saves do not publish changes. Sync runs on registry opening, foreground,
pull-to-refresh and edits. Failed requests retain pending changes across launches.
Acknowledgements do not overwrite newer local edits or switches. Between devices,
the last server-committed inventory edit wins; deletion wins over stale replay.
Deleting the active gym clears the selection rather than selecting another gym.

The task's Supabase paths predate the first-party data cutover. The additive
migration lives in the canonical `apps/web/db/migrations` directory. `gyms` uses
forced RLS with a transaction-local owner UUID derived from authenticated Jovie
account admission. Writes share the existing account/deletion lock. Its foreign
key cascades on account deletion; account export includes active gym records.
Native never connects to Postgres. No active choice is synced between devices.

Validation:

- `GymRegistryTests` is in the native test target and existing Unit plan. It
  covers CRUD, account separation, persistence, sync races and failure paths,
  including reopening the actual SQLite Core Data store.
- The existing `verify-training-mutations.py --postgres-bin <PostgreSQL16 bin>`
  runner applies the migration, runs `gym-registry-rls.sql` with a non-owner role,
  and exercises the actual gym adapter using disposable PostgreSQL transport.
- `pnpm db:schema:check` checks canonical migration placement. Existing web
  tests cover authenticated sync and exact equipment filtering.

Native runtime and coverage evidence must come from the real macOS runner.
Real-device TestFlight evidence remains with LYB-175.

## Implementation handoff

Validated on the Linux implementation host with Node 22.23.2 and pnpm 10.34.1:

```sh
pnpm lint
pnpm typecheck
pnpm test
taskset -c 0,1 pnpm test --concurrency=1
pnpm product:generate
pnpm product:check
pnpm db:schema:check
node scripts/check-vendor-boundaries.js
```

Final test validation uses sequential Turbo tasks and two available CPUs so
Vitest sizes its worker pool to the host. Default worker counts hit existing
guard tests' unchanged five-second timeouts; no test or gate was relaxed.

The database command used the host's extracted PostgreSQL 16.15 tools:

```sh
LD_LIBRARY_PATH=/tmp/lyb115-pg/root/usr/lib/x86_64-linux-gnu \
  python3 apps/web/db/tests/verify-training-mutations.py \
  --postgres-bin /tmp/lyb115-pg/root/usr/lib/postgresql/16/bin
```

It passed 51 checks including the gym RLS test and actual adapter tests. A second
run with `--gym-migration /tmp/lyb248-no-rls.sql`, a disposable copy with RLS
disabled, failed with `Unscoped request read gyms`, proving the isolation test
detects the regression. No live database was used.

`swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml` passed for
all nine changed Swift files; SourceKit-dependent rules were unavailable on this
host. Swift frontend parsing passed. The Xcode project passed `plutil -lint`,
and an XML comparison confirmed V5 preserves every V4 entity unchanged.
The 16 new XCTest cases are authored and wired into the test target, but their
execution, native build, migration runtime and coverage remain unverified here:
`xcodebuild -version` returned command not found. These need the real native
runner before rollout.

GBrain search could not connect to `127.0.0.1:7801`. No GBrain write or same-slug
readback was possible; this document holds the durable implementation notes.
