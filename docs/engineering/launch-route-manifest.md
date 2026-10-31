# Launch route and state manifest

LYB-271 supplies the manifest producer for LYB-183. From the repository root:

```sh
node scripts/lyb-launch-manifest.mjs /path/to/xctest-bindings.json > /path/to/manifest.json
```

The input is an object mapping each of the 13 launch path IDs to a nonempty
array of exact `TestClass/testMethod()` XCTest identifiers. LYB-183 supplies
these bindings from its implemented interaction and service tests. Missing,
unknown, duplicate, or malformed bindings fail with a nonzero exit and no JSON
output. The producer does not invent test selectors or emit an xcresult receipt.

The output uses `lyb-native-certification/v2`. It preserves the ordered primary
surfaces, all 87 surface dispositions (including web inventory and tombstones),
all required path tiers and captures, and the SHA-256 of the exact launch policy
fixture bytes. `routes` adds the timeline, stats/body score, and Jovi coach
state requirements: ready, denial, no-data, offline, stale, conflicting, unsafe
date, impossible date, expired date, and maintenance. Each state references the
oracle's required path IDs. These declarations describe required coverage;
they do not assert that the app implements or has passed those paths.

Before emitting, the producer reads the current `WorldClassScreen` registry in
`DesignSystem/Theme.swift` and `PaidAppSurface` in `MainTabViewPolicies.swift`.
An entry absent from the pinned surface map fails closed. New native screens
must use that canonical registry. Removed surfaces retain their policy
tombstones. Unsupported or missing registries also fail closed. Broader web
navigation, sheet exposure, and hide/delete enforcement remain with LYB-183;
the newer `web:/training/canvas` route requires that parent's scope reconciliation.

The schema fixtures are unchanged copies from [Jovie main at
065ba6f](https://github.com/JovieInc/Jovie/tree/065ba6ff9c06ad2de13b2297fcf48bc5e8c43035):

- `scripts/lyb-native-certification.mjs`
- `scripts/lyb-launch-contract.mjs`
- `scripts/fixtures/lyb-launch-contract.json`

Their local copies and SHA-256 receipt live in
`scripts/fixtures/lyb-certification/`. Update all three from a reviewed Jovie
revision together; formatting the policy JSON changes its certification digest.

The separate `scripts/surface-reconciliation.mjs` guard accepts reviewed new
static web routes in `scripts/fixtures/web-surface-additions.json` (schema
`lyb.web-surface-additions/v1`, with a `surfaces` map using the existing
`launch`, `repair`, `hide`, or `delete` dispositions). Declare new legal and
support routes there instead of rewriting the pinned upstream contract or
adding baseline debt. Local declarations cannot override a pinned disposition
or add native surfaces. Unlisted routes and reachable hidden/deleted routes
still fail; the immutable-base baseline ratchet remains enforced. Detect Changes
runs this guard and its negative controls on every PR. These local declarations
do not alter the native certification manifest or its digest.

`pnpm test --filter=@logyourbody/shared-lib` runs the schema and negative-control
tests through the existing test task. The scoped script command is:

```sh
node --experimental-vm-modules --test scripts/lyb-launch-manifest.test.mjs
```

The tests execute the unchanged oracle in a VM, with synthetic inputs confined
to the test process. The unrelated exposure adapter throws if invoked. Tests
check source digests, schema compatibility, every required state, new-screen
and new-mode rejection, malformed selectors, policy drift, CLI behavior, and
rejection of absent runtime evidence. Turbo inputs include both native
registries and all producer/fixture files so a cached pass cannot mask a new
registry entry.

Feed the emitted manifest and LYB-183's real receipt to the Jovie oracle for
certification. This slice does not provide native execution, installed-build,
TestFlight, or real-device proof.

## Installed-build xcresult coverage (LYB-289)

The evidence checker diffs an xcresult export against this manifest and the
pinned launch contract. Every contract path, and every route state (`ready`,
`denial`, `no-data`, `offline`, `stale`, `conflicting`, `unsafe-date`,
`impossible-date`, `expired-date`, and `maintenance`) on timeline, stats, and
coach, needs one passed native-interaction trace and one passed service trace.
The check fails when a path or state has no xcresult entry, when a trace is a
fixture substitute (`fixture`, `override`, `bypass`, or `-lybUITest`), or when
the installed build id is absent. A passing result is a
`lyb-native-certification/v2` receipt the pinned oracle can read. Checker tests
use synthetic exports and are not installed-build proof. JOV-6013 stays open.

```sh
node --experimental-strip-types --experimental-vm-modules --test \
  packages/shared-lib/scripts/installed-build-xcresult.behavior.mjs
node --experimental-strip-types packages/shared-lib/scripts/installed-build-xcresult.mjs \
  manifest.json \
  scripts/fixtures/lyb-certification/fixtures/lyb-launch-contract.json \
  xcresult-export.json
```
