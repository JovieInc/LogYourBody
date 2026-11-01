import Foundation

enum BodyVisualizationComposer {
    static func compose(
        _ request: BodyVisualizationRequest,
        existing: [BodyVisualizationSnapshot],
        makeId: () -> String
    ) throws -> BodyVisualizationSnapshot {
        if let priorId = request.retrospectiveOf {
            return try retrospective(priorId, request: request, existing: existing, makeId: makeId)
        }
        try validateIdentity(request)
        try validateTissues(request.evidence)
        try validateFfmi(request.evidence)
        let endpoints = try interpolationEndpoints(request, existing: existing)
        let links = request.evidence.map(link).sorted { $0.id < $1.id }
        let scale = supportedScale(request.evidence)
        let fit = fitAssessment(request, scaleSupported: scale.supported)
        let shape = shapeConstraint(request.evidence)
        let claim = anatomyClaim(request.representation)
        var snapshot = BodyVisualizationSnapshot(
            id: makeId(),
            accountId: request.accountId,
            frameId: "",
            frameRevisionAtComputation: 0,
            effectiveAt: request.effectiveAt,
            computedAt: request.computedAt,
            captures: request.captures.sorted { $0.id < $1.id },
            evidenceLinks: links,
            model: request.model,
            fitQuality: fit.primary,
            fitFlags: fit.flags,
            representation: request.representation,
            providerSourceDefinition: request.providerSourceDefinition,
            anatomyClaim: claim,
            shape: shape,
            interpolationEndpointIds: endpoints,
            retrospectiveOf: nil,
            asKnownThen: true,
            invalidated: false,
            invalidationReason: nil,
            idempotencyKey: ""
        )
        snapshot.idempotencyKey = fingerprint(snapshot)
        return snapshot
    }

    static func fingerprint(_ snapshot: BodyVisualizationSnapshot) -> String {
        let links = snapshot.evidenceLinks.map { link in
            [
                link.id,
                link.role.rawValue,
                link.recordKind.rawValue,
                link.epistemic.rawValue,
                link.sourceDefinition,
                link.stale ? "stale" : "fresh",
                link.conflictIds.sorted().joined(separator: ","),
                link.lineageIds.sorted().joined(separator: ","),
                link.rawObservationIds.sorted().joined(separator: ",")
            ].joined(separator: ":")
        }.joined(separator: "|")
        let captures = snapshot.captures.map { "\($0.id):\($0.viewpoint)" }.joined(separator: "|")
        return [
            snapshot.accountId,
            String(VisualizationClock.millis(snapshot.effectiveAt)),
            snapshot.representation.rawValue,
            snapshot.model.modelVersion,
            snapshot.model.calibrationVersion,
            snapshot.model.presentationVersion,
            snapshot.model.topologyId,
            snapshot.fitQuality.rawValue,
            snapshot.fitFlags.map(\.rawValue).joined(separator: ","),
            snapshot.providerSourceDefinition ?? "-",
            links,
            captures,
            snapshot.interpolationEndpointIds.sorted().joined(separator: "|"),
            snapshot.retrospectiveOf ?? "-",
            snapshot.asKnownThen ? "as-known-then" : "retrospective"
        ].joined(separator: "\n")
    }

    static func acceptsExistingPhotoKey(_ key: String, subject: String, ownerId: String) -> Bool {
        let owner = ownerId.lowercased()
        guard owner.range(
            of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil else { return false }
        let prefix = "progress-photos/\(subject)/accounts/\(owner)/"
        return key.hasPrefix(prefix) && !key.contains("..") && !key.contains("//")
    }

    static func assetKinds(for representation: VisualizationRepresentation) -> [VisualizationAssetKind] {
        switch representation {
        case .authenticPhoto:
            return [.original, .cache]
        case .personalizedInferredGeometry:
            return [.mask, .mesh, .texture, .cache]
        case .genericIllustration, .transitionalInterpolation:
            return [.cache]
        }
    }

    private static func retrospective(
        _ priorId: String,
        request: BodyVisualizationRequest,
        existing: [BodyVisualizationSnapshot],
        makeId: () -> String
    ) throws -> BodyVisualizationSnapshot {
        guard request.representation != .transitionalInterpolation,
              let prior = existing.first(where: { $0.id == priorId && $0.accountId == request.accountId })
        else { throw BodyVisualizationError.incompatibleInterpolation }
        guard validToken(request.accountId),
              validToken(request.model.modelVersion),
              validToken(request.model.calibrationVersion),
              validToken(request.model.presentationVersion),
              validToken(request.model.topologyId)
        else { throw BodyVisualizationError.invalidIdentity }
        guard request.model != prior.model else { throw BodyVisualizationError.invalidIdentity }
        var copy = prior
        copy.id = makeId()
        copy.computedAt = request.computedAt
        copy.model = request.model
        copy.retrospectiveOf = prior.id
        copy.asKnownThen = false
        copy.invalidated = false
        copy.invalidationReason = nil
        copy.idempotencyKey = fingerprint(copy)
        return copy
    }

    private static func validateIdentity(_ request: BodyVisualizationRequest) throws {
        guard validToken(request.accountId),
              validToken(request.model.modelVersion),
              validToken(request.model.calibrationVersion),
              validToken(request.model.presentationVersion),
              validToken(request.model.topologyId),
              request.evidence.allSatisfy({ $0.accountId == request.accountId && validToken($0.id) }),
              request.captures.allSatisfy({ validToken($0.id) && validToken($0.viewpoint) }),
              request.providerSourceDefinition.map(validToken) ?? true
        else { throw BodyVisualizationError.invalidIdentity }
        if request.representation == .authenticPhoto && request.captures.isEmpty {
            throw BodyVisualizationError.invalidIdentity
        }
        if request.evidence.contains(where: { $0.confidence.isFinite == false || !(0...1).contains($0.confidence) }) {
            throw BodyVisualizationError.invalidIdentity
        }
    }

    private static func validToken(_ value: String) -> Bool {
        guard (1...80).contains(value.count), !value.contains("/"), !value.contains("\\"), !value.contains("..") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "."
        }
    }

    private static func validateTissues(_ evidence: [CanonicalBodyEvidenceRef]) throws {
        var seen: [String: CanonicalBodyEvidenceRef.Role] = [:]
        for item in evidence {
            if let role = seen[item.id], role != item.role {
                throw BodyVisualizationError.tissueIdentityCollision
            }
            seen[item.id] = item.role
        }
    }

    private static func validateFfmi(_ evidence: [CanonicalBodyEvidenceRef]) throws {
        let ffmi = evidence.filter { $0.role == .ffmi }
        guard ffmi.count <= 1, let record = ffmi.first else { return }
        guard record.epistemic == .derived, record.recordKind == .estimate else {
            throw BodyVisualizationError.ffmiIndependentVote
        }
        let lineage = Set(record.lineageIds)
        let hasFatFreeMass = evidence.contains { $0.role == .fatFreeMass && lineage.contains($0.id) }
        let hasHeight = evidence.contains { $0.role == .height && lineage.contains($0.id) }
        guard hasFatFreeMass && hasHeight else { throw BodyVisualizationError.ffmiIndependentVote }
    }

    private static func interpolationEndpoints(
        _ request: BodyVisualizationRequest,
        existing: [BodyVisualizationSnapshot]
    ) throws -> [String] {
        guard request.representation == .transitionalInterpolation else {
            guard request.interpolationEndpointIds.isEmpty else { throw BodyVisualizationError.invalidIdentity }
            return []
        }
        let ids = request.interpolationEndpointIds
        guard Set(ids).count == 2, let first = ids.first, let second = ids.dropFirst().first else {
            throw BodyVisualizationError.incompatibleInterpolation
        }
        guard let left = existing.first(where: { $0.id == first && $0.accountId == request.accountId }),
              let right = existing.first(where: { $0.id == second && $0.accountId == request.accountId }),
              left.model == request.model, right.model == request.model,
              BodyVisualizationConsumer.progressComparisonAllowed(left, right)
        else { throw BodyVisualizationError.incompatibleInterpolation }
        return [first, second].sorted()
    }

    private static func link(_ evidence: CanonicalBodyEvidenceRef) -> VisualizationEvidenceLink {
        VisualizationEvidenceLink(
            id: evidence.id,
            role: evidence.role,
            recordKind: evidence.recordKind,
            epistemic: evidence.epistemic,
            sourceDefinition: evidence.sourceDefinition,
            stale: evidence.stale,
            conflictIds: evidence.conflictIds.sorted(),
            lineageIds: evidence.lineageIds.sorted(),
            rawObservationIds: evidence.rawObservationIds.sorted()
        )
    }

    private static func supportedScale(
        _ evidence: [CanonicalBodyEvidenceRef]
    ) -> (supported: Bool, evidenceId: String?) {
        let heights = evidence.filter { $0.role == .height }
        guard heights.count == 1, let height = heights.first, height.conflictIds.isEmpty else {
            return (false, heights.first?.id)
        }
        guard let magnitude = height.magnitude, magnitude.isFinite, magnitude > 0 else {
            return (false, height.id)
        }
        let supported: Bool
        switch height.unit {
        case "cm":
            supported = (50...275).contains(magnitude)
        case "m":
            supported = (0.5...2.75).contains(magnitude)
        default:
            supported = false
        }
        return (supported, height.id)
    }

    private static func fitAssessment(
        _ request: BodyVisualizationRequest,
        scaleSupported: Bool
    ) -> (primary: VisualizationFitQuality, flags: [VisualizationFitQuality]) {
        var flags: [VisualizationFitQuality] = []
        if request.representation == .personalizedInferredGeometry && !request.geometryKnown {
            flags.append(.unknownGeometry)
        }
        if request.evidence.contains(where: { !$0.conflictIds.isEmpty }) {
            flags.append(.conflictingInputs)
        }
        if !scaleSupported {
            flags.append(.unsupportedScale)
        }
        if request.evidence.contains(where: \.stale) {
            flags.append(.staleInputs)
        }
        let compositionRoles: Set<CanonicalBodyEvidenceRef.Role> = [
            .bodyFat, .fatFreeMass, .dxaLeanTissue, .skeletalMuscle
        ]
        let hasWeight = request.evidence.contains { $0.role == .weight }
        let hasComposition = request.evidence.contains { compositionRoles.contains($0.role) }
        if !hasWeight || !hasComposition {
            flags.append(.partial)
        }
        if flags.isEmpty {
            flags = [.fitted]
        }
        let priority: [VisualizationFitQuality] = [
            .unknownGeometry, .conflictingInputs, .unsupportedScale, .staleInputs, .partial, .fitted
        ]
        let primary = priority.first { flags.contains($0) } ?? .partial
        return (primary, flags)
    }

    private static func shapeConstraint(_ evidence: [CanonicalBodyEvidenceRef]) -> DatedShapeConstraint {
        let compositionRoles: Set<CanonicalBodyEvidenceRef.Role> = [
            .bodyFat, .fatFreeMass, .dxaLeanTissue, .skeletalMuscle
        ]
        let confidences = evidence.filter { $0.role != .ffmi }.map(\.confidence)
        return DatedShapeConstraint(
            weightEvidenceIds: evidence.filter { $0.role == .weight }.map(\.id).sorted(),
            compositionEvidenceIds: evidence.filter { compositionRoles.contains($0.role) }.map(\.id).sorted(),
            ffmiEvidenceId: evidence.first { $0.role == .ffmi }?.id,
            aggregateConfidence: confidences.min()
        )
    }

    private static func anatomyClaim(_ representation: VisualizationRepresentation) -> AnatomyClaimCeiling {
        switch representation {
        case .authenticPhoto:
            return .capture
        case .genericIllustration:
            return .illustration
        case .personalizedInferredGeometry:
            return .inferred
        case .transitionalInterpolation:
            return .interpolated
        }
    }
}
