# Versioned body visualization snapshots (LYB-315)

Parent: LYB-311. This layer stores visualization snapshots and their derived
files. It reads classifications JOV-6014 already published. It does not select
a source, fuse conflicts, import measurements, or choose the timeline date.

Claims stay inside [body-composition visual claims](../product/body-composition-visual-claims.md).
Storage stays inside [body-reconstruction consent](../architecture/body-reconstruction-consent.md):
no new reconstruction provider, credential, or upload. Home photo visibility
stays with [home photo visibility](../product/home-photo-visibility.md). This
slice does not change Home or `AvatarBodyRenderer`.

## Interface

Wireframes and personal reconstruction use `BodyVisualizationConsumer` and
`BodyVisualizationEntry` in `apps/ios/LogYourBody/Services/`.

- `BodyVisualizationConsumer.presentation(for:)` returns the representation,
  anatomy-claim ceiling, fit quality, and whether a wireframe or personal
  reconstruction may render. A wireframe is permitted only for a generic
  illustration. Personal reconstruction is permitted only for personalized
  inferred geometry whose fit is not unknown, conflicting, or an unsupported
  scale, and whose snapshot has not been invalidated. Stale inputs remain
  visible as fit quality and do not by themselves permit a measured-anatomy claim.
- `progressComparisonAllowed(_:_:)` is true only for two different snapshots of
  the same account, the same as-known-then or retrospective stance, and the same
  model, calibration, presentation, and topology. Transitional interpolation
  never counts as progress. A newer model is a different comparison key.
- `BodyVisualizationEntry.schedule` is the compose path. It is off unless
  Statsig gate `body_visualization_snapshots_v1` is enabled. Unknown flags are
  off. `finish` re-reads the live account session and selected date before it
  attaches files.
- `BodyVisualizationLedger` is the account-scoped store. Account deletion and
  metric correction call it directly. Those paths do not consult the gate.

Magnitudes are used only to decide whether one unconflicted height can support
scale (centimetres 50...275 or metres 0.5...2.75). The snapshot stores evidence
ids, roles, epistemic class, source definition, staleness, conflicts, lineage,
and raw observation ids. It does not store a second copy of the measurement.

## What a snapshot records

Each snapshot has capture ids and viewpoints, observation or estimate ids,
effective time, computation time, model/calibration/presentation versions,
topology id, the frame revision used at computation, and fit quality.

The stable personal frame is separate from the dated shape. A later side-view
capture increments the frame revision and can refresh supported scale. It does
not rewrite earlier snapshots' shape, evidence links, or frame revision. The
frame's calibration and topology stay on the version that created the frame.

Height supports scale. Weight and composition constrain a plausible dated shape.
`identifiesUnseenAnatomy` is always false; a payload that claims otherwise is
rejected. Provider output keeps its source definition. Representation is one of
authentic photo, generic illustration, personalized inferred geometry, or
transitional interpolation. There is no measured anatomy ceiling.

FFMI is accepted only as one derived estimate whose lineage includes the
fat-free-mass id and the height id in the same evidence set. Its confidence is
not part of the aggregate. Fat-free mass, DXA lean tissue, and skeletal muscle
stay distinct roles. Reusing one id for two roles is rejected.

An as-known-then snapshot stays on the model that computed it. A retrospective
copy changes identity, computation time, and model, keeps the prior shape and
frame revision, and is not progress against the as-known-then original.
Interpolation requires two comparable endpoints computed with the same model as
the interpolation request. A model upgrade cannot bridge older snapshots.

The same inputs, model, representation, and fit in the same session return the
original snapshot and job. A new account generation schedules a new job for that
same active snapshot. An invalidated snapshot is not reused.

## Assets, correction, and deletion

Jobs are idempotent and bound to account, session, generation, and effective
date. A completion after a date change, logout, account switch, generation
change, or deletion does not attach. The same completion retried in the original
session does not create a second mesh.

Authentic photos may reference an existing progress-photo object key
`progress-photos/{subject}/accounts/{ownerUuid}/...`. Any other key is rejected.
Derived masks, meshes, textures, and caches are local placeholder files under
Application Support `BodyVisualization/accounts/{accountId}/`. No image bytes
and no health values are written into telemetry.

A correction invalidates snapshots whose evidence id, lineage, raw observation
id, or capture id matches the corrected record, then deletes dependent local
derivatives. Source links and original photo files stay. `MetricCorrectionService`
passes the corrected metric id after a successful overlay write. Undo uses the
same path. Callers that compose snapshots must use that same id if a correction
should invalidate the drawing.

Account deletion uses `AccountDeletionCleanupService`. Product-account deletion,
which already removes owned progress photos, runs before local cleanup. Local
cleanup then purges the account directory and writes a tombstone. A relaunch
refuses new work for that account. Empty or partial ledger files migrate forward
inside schema version 1. A different schema version is rejected. Replaying a
migration is a no-op.

## LYB-64 evidence

Source proof is `BodyVisualizationSnapshotTests` on the existing iOS unit lane:

- `testSyntheticFixturesCoverSparseDatesConflictsAndLineage`
- `testUnknownGeometryProviderClaimAndModelUpgradeStayDistinct`
- `testSideViewRefinesFrameWithoutRewritingEarlierShape`
- `testRetrospectiveModelAndInterpolationDoNotInventProgress`
- `testFfmiIsLineageNotAnIndependentVoteAndTissuesStayDistinct`
- `testRetriesLateResponsesAndDeletionStayOnTheOriginalSession`
- `testCorrectionInvalidatesDerivativesAndKeepsSources`
- `testMigrationIsAdditiveAndReplayable`
- `testEntryGateRejectsSchedulingUntilEnabled`

Related wiring: `MetricCorrectionTests` records the corrected metric id, and
`AccountDeletionCleanupServiceTests/testPerformDeletionClearsVisualizationAssetsWithTheAuthorizedLocalCleanup`
keeps visualization purge in the authorized local-cleanup order. Fixtures use
synthetic sentinels only. They are not personal photos or health records.

The installed-build journeys below remain **UNVERIFIED** until the existing
LYB-64 authority runs them on the exact built head. This note does not change
the pinned launch contract.

| Journey                             | Required installed-build readback                                                                        |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Sparse dates                        | Dated drawings exist only where a snapshot was computed. A missing day is not filled in.                 |
| Old DXA and a later weight          | The DXA source definition stays DXA lean tissue. The later weight does not rename it to skeletal muscle. |
| Repeated import                     | The same session shows one snapshot and one job.                                                         |
| Conflicting inputs                  | Both observations remain, and the drawing is marked conflicting.                                         |
| Unknown geometry                    | Personal reconstruction stays unavailable. The provider name is unchanged.                               |
| Model upgrade                       | An older model and a newer model are not presented as the same progress comparison.                      |
| Side view                           | Frame revision advances. The earlier fat and muscle state stays.                                         |
| Retrospective model                 | The new model is labeled retrospective and is not compared as progress against as-known-then.            |
| Interpolation                       | A bridge is visible as interpolation and is not a progress comparison.                                   |
| Correction                          | Derived files disappear. The source observation and original photo remain.                               |
| Deletion and relaunch               | Local masks, meshes, textures, caches, and the ledger are gone. A late job cannot attach.                |
| Date change, logout, account switch | A late provider response does not attach to the new date, signed-out session, or other account.          |

Simulator, physical-device, and distributed-build evidence for those journeys
are absent. Source tests do not close LYB-64.
