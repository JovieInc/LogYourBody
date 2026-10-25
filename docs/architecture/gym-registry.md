# Gym registry (LYB-248)

`gym_registry_v1` is the default-off native Statsig gate for Settings → Gyms.
Users register and edit gyms, explicitly confirm inventory, and select a gym
manually. Registration and remote discovery never select a gym. Deleting the
selected gym clears the selection. The last manual choice is device-local and
account-scoped; it survives launches and may always be cleared.

Core Data V5 adds `CachedGymRegistry` without changing retained V4 entities. Its
owner-scoped snapshot stores gym details, selection, pending upserts, and pending
deletions. Local writes complete before the UI acknowledges them. Sync runs on
opening the screen, local changes, retry, and pull to refresh. Failed requests
retain their journal; late responses cannot discard concurrent edits or mutate a
different account lifetime. Concurrent device edits use the last server write;
deleted gym IDs cannot be revived. An edit conflicting with a remote deletion
remains pending and visible until the user deletes that local gym.

The current source uses **Neon and Jovie bearer authentication**, not the retired
Supabase data plane named in the original issue. The additive migration therefore
lives in `apps/web/db/migrations`, with SQL isolation tests in `apps/web/db/tests`.
The first-party adapter sets transaction-local `app.user_subject`; RLS and explicit
owner predicates protect reads/writes, and account-admission locks fence writes
against account deletion. The account foreign key cascades deletions. Account
export includes gyms. No location API or location permission is used.

Bearer endpoints:

- `GET /api/auth/mobile/sync/v1/gyms` returns `{ gyms: Gym[] }` for the caller.
- `POST` to that path saves `{ id, name, region?, equipment, preferredMachines }`.
  Region is optional coarse text, equipment is an explicit array of catalog IDs,
  and machine preferences are labels that never add inventory. Successful writes
  return `{ gym }`; an ID conflict returns 409.
- `DELETE` accepts `{ id }` and returns `{ deleted: id }`. Replays are safe and
  leave a server tombstone so stale clients cannot revive deleted rows.
- `GET /api/auth/mobile/training/v1/exercises` accepts optional `equipment`, a
  comma-separated set from the active gym. Omitted means unrestricted; an empty
  value means a confirmed empty inventory. Every required item must be present.
  This library query does not modify engine prescriptions or training enrollment.

Validation:

```sh
pnpm lint
pnpm typecheck
pnpm test
pnpm db:schema:check
python3 apps/web/db/tests/verify-gym-registry.py --postgres-bin /path/to/pg16/bin
```

The SQL assertions also run in the existing `verify-training-mutations.py` runner.
`GymRegistryTests` belongs to the native unit test target, including SQLite reopen,
manual switching, offline retry, failed writes, and account-lifetime cases. Native
execution and coverage require the repository's macOS runner; SwiftLint alone is
not that evidence. Real-device TestFlight evidence remains with LYB-175.
