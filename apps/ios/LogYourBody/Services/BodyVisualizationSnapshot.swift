import Foundation

/// Visualization snapshots consume classifications JOV-6014 already published.
/// This file does not select sources, fuse conflicts, import measurements, or
/// choose the timeline date. Magnitudes are read only to decide whether height
/// can support scale, then dropped. They are not a second metric record.
enum BodyVisualizationSchema {
    static let current = 1
}

enum BodyVisualizationError: Error, Equatable {
    case featureDisabled
    case signedOut
    case accountMismatch
    case ffmiIndependentVote
    case tissueIdentityCollision
    case incompatibleInterpolation
    case foreignProviderKey
    case invalidIdentity
    case uniqueAnatomyClaim
    case unsupportedSchema(Int)
    case deleted
    case unavailable
    case session(VisualizationAttachRejection)
}

enum VisualizationAttachRejection: String, Codable, Equatable, Sendable {
    case accountMismatch
    case sessionMismatch
    case generationMismatch
    case dateChanged
    case loggedOut
    case deleted
    case missingJob
}

struct CanonicalBodyEvidenceRef: Equatable, Sendable {
    enum RecordKind: String, Codable, Sendable {
        case observation
        case estimate
    }

    enum Role: String, Codable, Sendable {
        case height
        case weight
        case bodyFat
        case fatFreeMass
        case dxaLeanTissue
        case skeletalMuscle
        case ffmi
    }

    /// Classes published by the canonical reader. Visualization does not rename them.
    enum Epistemic: String, Codable, Sendable {
        case measured
        case derived
        case inferred
        case predicted
    }

    var id: String
    var accountId: String
    var recordKind: RecordKind
    var role: Role
    var epistemic: Epistemic
    var effectiveAt: Date
    var sourceDefinition: String
    var confidence: Double
    var stale: Bool
    var conflictIds: [String]
    var lineageIds: [String]
    var rawObservationIds: [String]
    /// Present only for the scale decision. Never written onto a snapshot.
    var magnitude: Double?
    var unit: String?
}

struct VisualizationEvidenceLink: Codable, Equatable, Sendable {
    var id: String
    var role: CanonicalBodyEvidenceRef.Role
    var recordKind: CanonicalBodyEvidenceRef.RecordKind
    var epistemic: CanonicalBodyEvidenceRef.Epistemic
    var sourceDefinition: String
    var stale: Bool
    var conflictIds: [String]
    var lineageIds: [String]
    var rawObservationIds: [String]
}

struct VisualizationCaptureRef: Codable, Equatable, Sendable {
    var id: String
    var viewpoint: String
}

enum VisualizationRepresentation: String, Codable, Sendable {
    case authenticPhoto
    case genericIllustration
    case personalizedInferredGeometry
    case transitionalInterpolation
}

enum VisualizationFitQuality: String, Codable, Sendable {
    case fitted
    case partial
    case unknownGeometry
    case unsupportedScale
    case conflictingInputs
    case staleInputs
}

/// What a picture is allowed to say about anatomy. There is no measured case:
/// a provider mesh or illustration cannot be renamed into directly measured anatomy.
enum AnatomyClaimCeiling: String, Codable, Sendable {
    case capture
    case illustration
    case inferred
    case interpolated
}

struct VisualizationModelIdentity: Codable, Equatable, Sendable {
    var modelVersion: String
    var calibrationVersion: String
    var presentationVersion: String
    var topologyId: String
}

struct VisualizationWorkPermit: Codable, Equatable, Sendable {
    var accountId: String
    var sessionId: String
    var generation: UInt64
    var effectiveAt: Date
    var acceptsAttachments: Bool
    var deleted: Bool
}

struct PersonalFrameIdentity: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var accountId: String
    var revision: Int
    var topologyId: String
    var calibrationVersion: String
    var scaleSupported: Bool
    var scaleEvidenceId: String?
    var refiningCaptureIds: [String]
    var updatedAt: Date
}

struct DatedShapeConstraint: Codable, Equatable, Sendable {
    var weightEvidenceIds: [String]
    var compositionEvidenceIds: [String]
    var ffmiEvidenceId: String?
    /// Weight and composition bound a plausible dated shape. They do not identify unseen anatomy.
    let identifiesUnseenAnatomy: Bool
    var aggregateConfidence: Double?

    init(
        weightEvidenceIds: [String],
        compositionEvidenceIds: [String],
        ffmiEvidenceId: String?,
        aggregateConfidence: Double?
    ) {
        self.weightEvidenceIds = weightEvidenceIds
        self.compositionEvidenceIds = compositionEvidenceIds
        self.ffmiEvidenceId = ffmiEvidenceId
        self.identifiesUnseenAnatomy = false
        self.aggregateConfidence = aggregateConfidence
    }

    private enum CodingKeys: String, CodingKey {
        case weightEvidenceIds
        case compositionEvidenceIds
        case ffmiEvidenceId
        case identifiesUnseenAnatomy
        case aggregateConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weightEvidenceIds = try container.decodeIfPresent([String].self, forKey: .weightEvidenceIds) ?? []
        compositionEvidenceIds = try container.decodeIfPresent([String].self, forKey: .compositionEvidenceIds) ?? []
        ffmiEvidenceId = try container.decodeIfPresent(String.self, forKey: .ffmiEvidenceId)
        let claimed = try container.decodeIfPresent(Bool.self, forKey: .identifiesUnseenAnatomy) ?? false
        guard claimed == false else { throw BodyVisualizationError.uniqueAnatomyClaim }
        identifiesUnseenAnatomy = false
        aggregateConfidence = try container.decodeIfPresent(Double.self, forKey: .aggregateConfidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weightEvidenceIds, forKey: .weightEvidenceIds)
        try container.encode(compositionEvidenceIds, forKey: .compositionEvidenceIds)
        try container.encodeIfPresent(ffmiEvidenceId, forKey: .ffmiEvidenceId)
        try container.encode(false, forKey: .identifiesUnseenAnatomy)
        try container.encodeIfPresent(aggregateConfidence, forKey: .aggregateConfidence)
    }
}

struct BodyVisualizationSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var accountId: String
    var frameId: String
    var frameRevisionAtComputation: Int
    var effectiveAt: Date
    var computedAt: Date
    var captures: [VisualizationCaptureRef]
    var evidenceLinks: [VisualizationEvidenceLink]
    var model: VisualizationModelIdentity
    var fitQuality: VisualizationFitQuality
    var fitFlags: [VisualizationFitQuality]
    var representation: VisualizationRepresentation
    var providerSourceDefinition: String?
    var anatomyClaim: AnatomyClaimCeiling
    var shape: DatedShapeConstraint
    var interpolationEndpointIds: [String]
    var retrospectiveOf: String?
    var asKnownThen: Bool
    var invalidated: Bool
    var invalidationReason: String?
    var idempotencyKey: String

    var observationIds: [String] {
        evidenceLinks.filter { $0.recordKind == .observation }.map(\.id).sorted()
    }

    var estimateIds: [String] {
        evidenceLinks.filter { $0.recordKind == .estimate }.map(\.id).sorted()
    }

    var rawObservationIds: [String] {
        Set(observationIds + evidenceLinks.flatMap(\.rawObservationIds)).sorted()
    }
}

enum VisualizationAssetKind: String, Codable, CaseIterable, Sendable {
    case original
    case mask
    case mesh
    case texture
    case cache
}

struct VisualizationAssetRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var accountId: String
    var snapshotId: String
    var jobId: String
    var kind: VisualizationAssetKind
    var localRelativePath: String?
    var providerObjectKey: String?
    var invalidated: Bool
}

struct VisualizationAssetJob: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var accountId: String
    var idempotencyKey: String
    var sessionKey: String
    var permit: VisualizationWorkPermit
    var snapshotId: String?
    var state: String
}

struct VisualizationLedgerDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var frames: [PersonalFrameIdentity]
    var snapshots: [BodyVisualizationSnapshot]
    var jobs: [VisualizationAssetJob]
    var assets: [VisualizationAssetRecord]

    static let empty = VisualizationLedgerDocument(
        schemaVersion: BodyVisualizationSchema.current,
        frames: [],
        snapshots: [],
        jobs: [],
        assets: []
    )

    init(
        schemaVersion: Int,
        frames: [PersonalFrameIdentity],
        snapshots: [BodyVisualizationSnapshot],
        jobs: [VisualizationAssetJob],
        assets: [VisualizationAssetRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.frames = frames
        self.snapshots = snapshots
        self.jobs = jobs
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case frames
        case snapshots
        case jobs
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? BodyVisualizationSchema.current
        guard version == BodyVisualizationSchema.current else {
            throw BodyVisualizationError.unsupportedSchema(version)
        }
        schemaVersion = BodyVisualizationSchema.current
        frames = try container.decodeIfPresent([PersonalFrameIdentity].self, forKey: .frames) ?? []
        snapshots = try container.decodeIfPresent([BodyVisualizationSnapshot].self, forKey: .snapshots) ?? []
        jobs = try container.decodeIfPresent([VisualizationAssetJob].self, forKey: .jobs) ?? []
        assets = try container.decodeIfPresent([VisualizationAssetRecord].self, forKey: .assets) ?? []
        guard snapshots.allSatisfy({ $0.shape.identifiesUnseenAnatomy == false }) else {
            throw BodyVisualizationError.uniqueAnatomyClaim
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(frames, forKey: .frames)
        try container.encode(snapshots, forKey: .snapshots)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(assets, forKey: .assets)
    }
}

struct BodyVisualizationRequest: Equatable, Sendable {
    var accountId: String
    var effectiveAt: Date
    var computedAt: Date
    var evidence: [CanonicalBodyEvidenceRef]
    var captures: [VisualizationCaptureRef]
    var model: VisualizationModelIdentity
    var representation: VisualizationRepresentation
    var providerSourceDefinition: String?
    var geometryKnown: Bool
    var interpolationEndpointIds: [String] = []
    var retrospectiveOf: String?
    var existingPhotoObjectKey: String?
    var productOwnerId: String?
}

struct ScheduledVisualization: Equatable, Sendable {
    var job: VisualizationAssetJob
    var snapshot: BodyVisualizationSnapshot
}

struct BodyVisualizationPresentation: Equatable, Sendable {
    var representation: VisualizationRepresentation
    var anatomyClaim: AnatomyClaimCeiling
    var fitQuality: VisualizationFitQuality
    var wireframePermitted: Bool
    var personalReconstructionPermitted: Bool
    var progressComparisonKey: String?
}

struct BodyVisualizationDeletionPlan: Equatable, Sendable {
    var accountId: String
    var kinds: [VisualizationAssetKind]
    var providerObjectKeys: [String]
    /// Originals that already live in the progress-photo store are removed by that store's account deletion.
    var delegatesProviderOriginalsToExistingPhotoLifecycle: Bool
}

enum VisualizationClock {
    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

enum BodyVisualizationConsumer {
    /// Wireframes may render a generic illustration only. Personal reconstruction may
    /// render inferred geometry only, and only with the provider definition left intact.
    static func presentation(for snapshot: BodyVisualizationSnapshot) -> BodyVisualizationPresentation {
        let blocked: Set<VisualizationFitQuality> = [.unknownGeometry, .conflictingInputs, .unsupportedScale]
        let usable = !snapshot.invalidated && snapshot.shape.identifiesUnseenAnatomy == false
        let wireframe = usable && snapshot.representation == .genericIllustration
        let reconstruction = usable
            && snapshot.representation == .personalizedInferredGeometry
            && snapshot.anatomyClaim == .inferred
            && !blocked.contains(snapshot.fitQuality)
        return BodyVisualizationPresentation(
            representation: snapshot.representation,
            anatomyClaim: snapshot.anatomyClaim,
            fitQuality: snapshot.fitQuality,
            wireframePermitted: wireframe,
            personalReconstructionPermitted: reconstruction,
            progressComparisonKey: usable ? progressComparisonKey(snapshot) : nil
        )
    }

    static func progressComparisonAllowed(
        _ left: BodyVisualizationSnapshot,
        _ right: BodyVisualizationSnapshot
    ) -> Bool {
        guard left.id != right.id, left.accountId == right.accountId else { return false }
        guard !left.invalidated, !right.invalidated else { return false }
        guard left.asKnownThen == right.asKnownThen else { return false }
        guard left.model == right.model else { return false }
        guard left.representation != .transitionalInterpolation,
              right.representation != .transitionalInterpolation else { return false }
        guard left.shape.identifiesUnseenAnatomy == false,
              right.shape.identifiesUnseenAnatomy == false else { return false }
        return progressComparisonKey(left) == progressComparisonKey(right)
    }

    static func progressComparisonKey(_ snapshot: BodyVisualizationSnapshot) -> String {
        [
            snapshot.accountId,
            snapshot.model.modelVersion,
            snapshot.model.calibrationVersion,
            snapshot.model.presentationVersion,
            snapshot.model.topologyId,
            snapshot.asKnownThen ? "as-known-then" : "retrospective"
        ].joined(separator: "\n")
    }
}
