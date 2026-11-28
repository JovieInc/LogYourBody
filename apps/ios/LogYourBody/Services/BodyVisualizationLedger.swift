import Foundation

/// Account-scoped visualization jobs and derived files. Photo bytes stay with the
/// existing photo store. A late completion cannot attach after the session, date,
/// account, or deletion changes.
actor BodyVisualizationLedger {
    nonisolated static let shared: BodyVisualizationLedger = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BodyVisualization", isDirectory: true)
        return BodyVisualizationLedger(rootURL: root)
    }()

    private let rootURL: URL
    private let makeId: @Sendable () -> String
    private let encoder: JSONEncoder
    private var livePermit: VisualizationWorkPermit?
    private var attachmentsOpen = false
    private var memory: [String: VisualizationLedgerDocument] = [:]

    init(rootURL: URL, makeId: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.rootURL = rootURL
        self.makeId = makeId
        self.encoder = BodyVisualizationMigration.encoder()
    }

    func bind(_ permit: VisualizationWorkPermit) throws {
        try rejectIfDeleted(permit.accountId)
        guard permit.accountId.isEmpty == false else { throw BodyVisualizationError.invalidIdentity }
        livePermit = permit
        attachmentsOpen = permit.acceptsAttachments && !permit.deleted
    }

    func noteSignedOut() {
        attachmentsOpen = false
        livePermit = nil
    }

    func schedule(
        _ request: BodyVisualizationRequest,
        permit: VisualizationWorkPermit
    ) throws -> ScheduledVisualization {
        try requireLive(permit)
        guard request.accountId == permit.accountId, request.effectiveAt == permit.effectiveAt else {
            throw BodyVisualizationError.session(.dateChanged)
        }
        var document = try load(permit.accountId)
        let drafted = try BodyVisualizationComposer.compose(request, existing: document.snapshots, makeId: makeId)
        let snapshot = try place(drafted, request: request, permit: permit, document: &document)
        let sessionKey = sessionKey(snapshot.idempotencyKey, permit)
        if let existing = document.jobs.first(where: {
            $0.sessionKey == sessionKey && $0.snapshotId == snapshot.id && $0.accountId == permit.accountId
        }) {
            try save(document, accountId: permit.accountId)
            return ScheduledVisualization(job: existing, snapshot: snapshot)
        }
        let job = VisualizationAssetJob(
            id: makeId(),
            accountId: permit.accountId,
            idempotencyKey: snapshot.idempotencyKey,
            sessionKey: sessionKey,
            permit: permit,
            snapshotId: snapshot.id,
            state: "queued"
        )
        document.jobs.append(job)
        try save(document, accountId: permit.accountId)
        return ScheduledVisualization(job: job, snapshot: snapshot)
    }

    func finish(
        jobId: String,
        permit: VisualizationWorkPermit,
        existingPhotoObjectKey: String? = nil,
        productOwnerId: String? = nil
    ) throws -> VisualizationAttachResult {
        if tombstoned(permit.accountId) || permit.deleted {
            return .rejected(.deleted)
        }
        guard attachmentsOpen, let live = livePermit else { return .rejected(.loggedOut) }
        if let key = existingPhotoObjectKey {
            guard let owner = productOwnerId,
                  BodyVisualizationComposer.acceptsExistingPhotoKey(key, subject: permit.accountId, ownerId: owner)
            else { throw BodyVisualizationError.foreignProviderKey }
        }
        guard var document = try? load(permit.accountId),
              let index = document.jobs.firstIndex(where: { $0.id == jobId })
        else { return .rejected(.missingJob) }
        let job = document.jobs[index]
        if let rejection = rejection(job: job, presented: permit, live: live) {
            return .rejected(rejection)
        }
        if job.state == "completed" {
            return .idempotent(job)
        }
        guard let snapshot = document.snapshots.first(where: { $0.id == job.snapshotId }) else {
            throw BodyVisualizationError.unavailable
        }
        var records: [VisualizationAssetRecord] = []
        for kind in BodyVisualizationComposer.assetKinds(for: snapshot.representation) {
            let id = makeId()
            let relative = "assets/\(id).bin"
            let provider = kind == .original ? existingPhotoObjectKey : nil
            records.append(VisualizationAssetRecord(
                id: id,
                accountId: permit.accountId,
                snapshotId: snapshot.id,
                jobId: job.id,
                kind: kind,
                localRelativePath: relative,
                providerObjectKey: provider,
                invalidated: false
            ))
            try writePlaceholder(accountId: permit.accountId, relativePath: relative)
        }
        document.assets.append(contentsOf: records)
        document.jobs[index].state = "completed"
        try save(document, accountId: permit.accountId)
        return .attached(document.jobs[index])
    }

    func refineFrame(
        accountId: String,
        capture: VisualizationCaptureRef,
        at: Date,
        permit: VisualizationWorkPermit
    ) throws -> PersonalFrameIdentity {
        try requireLive(permit)
        guard permit.accountId == accountId else { throw BodyVisualizationError.accountMismatch }
        var document = try load(accountId)
        guard let index = document.frames.firstIndex(where: { $0.accountId == accountId }) else {
            throw BodyVisualizationError.unavailable
        }
        document.frames[index].revision += 1
        if !document.frames[index].refiningCaptureIds.contains(capture.id) {
            document.frames[index].refiningCaptureIds.append(capture.id)
        }
        document.frames[index].updatedAt = at
        let snapshotRevisions = document.snapshots.map(\.frameRevisionAtComputation)
        let shapes = document.snapshots.map(\.shape)
        try save(document, accountId: accountId)
        guard document.snapshots.map(\.frameRevisionAtComputation) == snapshotRevisions,
              document.snapshots.map(\.shape) == shapes
        else { throw BodyVisualizationError.unavailable }
        return document.frames[index]
    }

    func invalidateDerivatives(accountId: String, evidenceIds: [String]) throws {
        guard fileExists(ledgerURL(accountId)) else { return }
        var document = try load(accountId)
        let ids = Set(evidenceIds)
        guard ids.isEmpty == false else { return }
        for index in document.snapshots.indices {
            let snapshot = document.snapshots[index]
            let referenced = Set(
                snapshot.evidenceLinks.flatMap { [$0.id] + $0.lineageIds + $0.rawObservationIds }
                    + snapshot.captures.map(\.id)
            )
            guard referenced.isDisjoint(with: ids) == false else { continue }
            document.snapshots[index].invalidated = true
            document.snapshots[index].invalidationReason = "correction"
            for assetIndex in document.assets.indices where document.assets[assetIndex].snapshotId == snapshot.id {
                guard document.assets[assetIndex].kind != .original else { continue }
                document.assets[assetIndex].invalidated = true
                if let relative = document.assets[assetIndex].localRelativePath {
                    try removeFile(accountId: accountId, relativePath: relative)
                }
                document.assets[assetIndex].localRelativePath = nil
            }
        }
        try save(document, accountId: accountId)
    }

    func deletionPlan(accountId: String) throws -> BodyVisualizationDeletionPlan {
        let document = (try? load(accountId)) ?? .empty
        let kinds = VisualizationAssetKind.allCases.filter { kind in
            document.assets.contains { $0.accountId == accountId && $0.kind == kind }
        }
        let keys = document.assets.compactMap(\.providerObjectKey).sorted()
        return BodyVisualizationDeletionPlan(
            accountId: accountId,
            kinds: kinds,
            providerObjectKeys: keys,
            delegatesProviderOriginalsToExistingPhotoLifecycle: !keys.isEmpty
        )
    }

    func purge(accountId: String) throws {
        guard validAccount(accountId) else { throw BodyVisualizationError.invalidIdentity }
        let directory = accountDirectory(accountId)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try writeTombstone(accountId)
        memory[accountId] = nil
        if livePermit?.accountId == accountId {
            livePermit = nil
            attachmentsOpen = false
        }
    }

    func snapshotCount(accountId: String) throws -> Int {
        (try? load(accountId))?.snapshots.count ?? 0
    }

    func document(accountId: String) throws -> VisualizationLedgerDocument {
        try load(accountId)
    }

    private func place(
        _ drafted: BodyVisualizationSnapshot,
        request: BodyVisualizationRequest,
        permit: VisualizationWorkPermit,
        document: inout VisualizationLedgerDocument
    ) throws -> BodyVisualizationSnapshot {
        if let existing = document.snapshots.first(where: {
            $0.idempotencyKey == drafted.idempotencyKey && !$0.invalidated && $0.accountId == permit.accountId
        }) {
            return existing
        }
        var snapshot = drafted
        let heights = request.evidence.filter { $0.role == .height }
        if let index = document.frames.firstIndex(where: { $0.accountId == permit.accountId }) {
            // A retrospective copy keeps the frame revision the prior shape was computed against.
            if request.retrospectiveOf == nil {
                snapshot.frameId = document.frames[index].id
                snapshot.frameRevisionAtComputation = document.frames[index].revision
            }
            if request.retrospectiveOf == nil, heights.count == 1, let height = heights.first {
                let supported = snapshot.fitFlags.contains(.unsupportedScale) == false
                document.frames[index].scaleSupported = supported
                document.frames[index].scaleEvidenceId = height.id
            }
        } else if request.retrospectiveOf == nil {
            let frame = PersonalFrameIdentity(
                id: makeId(),
                accountId: permit.accountId,
                revision: 1,
                topologyId: request.model.topologyId,
                calibrationVersion: request.model.calibrationVersion,
                scaleSupported: heights.count == 1 && snapshot.fitFlags.contains(.unsupportedScale) == false,
                scaleEvidenceId: heights.count == 1 ? heights.first?.id : nil,
                refiningCaptureIds: [],
                updatedAt: request.computedAt
            )
            document.frames.append(frame)
            snapshot.frameId = frame.id
            snapshot.frameRevisionAtComputation = frame.revision
        }
        document.snapshots.append(snapshot)
        return snapshot
    }

    private func requireLive(_ permit: VisualizationWorkPermit) throws {
        try rejectIfDeleted(permit.accountId)
        guard attachmentsOpen, let live = livePermit else { throw BodyVisualizationError.signedOut }
        guard live == permit else { throw BodyVisualizationError.session(permitRejection(presented: permit, live: live)) }
    }

    private func permitRejection(
        presented: VisualizationWorkPermit,
        live: VisualizationWorkPermit
    ) -> VisualizationAttachRejection {
        if presented.deleted || live.deleted { return .deleted }
        if !live.acceptsAttachments || !presented.acceptsAttachments { return .loggedOut }
        if presented.accountId != live.accountId { return .accountMismatch }
        if presented.sessionId != live.sessionId { return .sessionMismatch }
        if presented.generation != live.generation { return .generationMismatch }
        if presented.effectiveAt != live.effectiveAt { return .dateChanged }
        return .sessionMismatch
    }

    private func rejection(
        job: VisualizationAssetJob,
        presented: VisualizationWorkPermit,
        live: VisualizationWorkPermit
    ) -> VisualizationAttachRejection? {
        if presented.deleted || live.deleted { return .deleted }
        if !live.acceptsAttachments || !presented.acceptsAttachments { return .loggedOut }
        if presented.accountId != job.accountId || presented.accountId != live.accountId {
            return .accountMismatch
        }
        if presented.sessionId != job.permit.sessionId || presented.sessionId != live.sessionId {
            return .sessionMismatch
        }
        if presented.generation != job.permit.generation || presented.generation != live.generation {
            return .generationMismatch
        }
        if presented.effectiveAt != job.permit.effectiveAt || presented.effectiveAt != live.effectiveAt {
            return .dateChanged
        }
        return nil
    }

    private func sessionKey(_ idempotencyKey: String, _ permit: VisualizationWorkPermit) -> String {
        "\(idempotencyKey)\n\(permit.sessionId)\n\(permit.generation)"
    }

    private func rejectIfDeleted(_ accountId: String) throws {
        if tombstoned(accountId) { throw BodyVisualizationError.deleted }
    }

    private func load(_ accountId: String) throws -> VisualizationLedgerDocument {
        guard validAccount(accountId) else { throw BodyVisualizationError.invalidIdentity }
        if let cached = memory[accountId] { return cached }
        let url = ledgerURL(accountId)
        guard fileExists(url) else { return .empty }
        let data = try Data(contentsOf: url)
        let document = try BodyVisualizationMigration.migrate(data)
        memory[accountId] = document
        return document
    }

    private func save(_ document: VisualizationLedgerDocument, accountId: String) throws {
        guard validAccount(accountId) else { throw BodyVisualizationError.invalidIdentity }
        try rejectIfDeleted(accountId)
        let directory = accountDirectory(accountId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: ledgerURL(accountId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        memory[accountId] = document
    }

    private func writePlaceholder(accountId: String, relativePath: String) throws {
        let url = accountDirectory(accountId).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func removeFile(accountId: String, relativePath: String) throws {
        let url = accountDirectory(accountId).appendingPathComponent(relativePath)
        guard fileExists(url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func writeTombstone(_ accountId: String) throws {
        let directory = rootURL.appendingPathComponent("tombstones", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data("{\"schemaVersion\":1}".utf8)
        try payload.write(
            to: directory.appendingPathComponent(accountId),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func tombstoned(_ accountId: String) -> Bool {
        fileExists(rootURL.appendingPathComponent("tombstones", isDirectory: true).appendingPathComponent(accountId))
    }

    private func ledgerURL(_ accountId: String) -> URL {
        accountDirectory(accountId).appendingPathComponent("ledger.json")
    }

    private func accountDirectory(_ accountId: String) -> URL {
        rootURL.appendingPathComponent("accounts", isDirectory: true).appendingPathComponent(accountId, isDirectory: true)
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func validAccount(_ accountId: String) -> Bool {
        guard (1...200).contains(accountId.count), accountId != ".", accountId != ".." else { return false }
        return !accountId.contains("/") && !accountId.contains("\\") && !accountId.contains("..")
    }
}

enum VisualizationAttachResult: Equatable, Sendable {
    case attached(VisualizationAssetJob)
    case idempotent(VisualizationAssetJob)
    case rejected(VisualizationAttachRejection)
}

enum BodyVisualizationMigration {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func migrate(_ data: Data) throws -> VisualizationLedgerDocument {
        if data.isEmpty { return .empty }
        let document = try decoder().decode(VisualizationLedgerDocument.self, from: data)
        guard document.snapshots.allSatisfy({ $0.shape.identifiesUnseenAnatomy == false }) else {
            throw BodyVisualizationError.uniqueAnatomyClaim
        }
        return document
    }
}

/// Production entry for wireframes and personal reconstruction. The gate stays off
/// until a consumer is rolled out. Deletion and correction do not consult the gate.
@MainActor
struct BodyVisualizationEntry {
    static let featureGate = "body_visualization_snapshots_v1"

    var isEnabled: @MainActor () -> Bool
    var currentPermit: @MainActor (Date) -> VisualizationWorkPermit?
    var ledger: BodyVisualizationLedger

    init(
        isEnabled: @escaping @MainActor () -> Bool = {
            AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: BodyVisualizationEntry.featureGate)
        },
        currentPermit: @escaping @MainActor (Date) -> VisualizationWorkPermit? = { effectiveAt in
            guard let ownership = AuthManager.shared.captureAccountSession() else { return nil }
            return VisualizationWorkPermit(
                accountId: ownership.subject,
                sessionId: "\(ownership.subject)#\(ownership.generation)",
                generation: ownership.generation,
                effectiveAt: effectiveAt,
                acceptsAttachments: true,
                deleted: false
            )
        },
        ledger: BodyVisualizationLedger? = nil
    ) {
        self.isEnabled = isEnabled
        self.currentPermit = currentPermit
        self.ledger = ledger ?? .shared
    }

    func schedule(_ request: BodyVisualizationRequest) async throws -> ScheduledVisualization {
        guard isEnabled() else { throw BodyVisualizationError.featureDisabled }
        guard let permit = currentPermit(request.effectiveAt) else { throw BodyVisualizationError.signedOut }
        try await ledger.bind(permit)
        return try await ledger.schedule(request, permit: permit)
    }

    func finish(
        jobId: String,
        effectiveAt: Date,
        existingPhotoObjectKey: String? = nil,
        productOwnerId: String? = nil
    ) async throws -> VisualizationAttachResult {
        guard let permit = currentPermit(effectiveAt) else {
            await ledger.noteSignedOut()
            return .rejected(.loggedOut)
        }
        try await ledger.bind(permit)
        return try await ledger.finish(
            jobId: jobId,
            permit: permit,
            existingPhotoObjectKey: existingPhotoObjectKey,
            productOwnerId: productOwnerId
        )
    }
}
