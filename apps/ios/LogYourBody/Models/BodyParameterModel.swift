import Foundation

/// Explicit illustration families, never inferred from measurements or goals.
enum BodyParameterFamily: String, Codable, CaseIterable, Sendable {
    case male
    case female
}

/// Continuous artistic coordinates, not percentages, tissue masses, or targets.
struct BodyParameterValues: Codable, Equatable, Sendable {
    let adiposity: Double
    let muscularity: Double
    let proportion: Double
}

/// Normalized engineering limits, not physiological reference ranges.
struct BodyParameterRanges: Equatable, Sendable {
    let adiposity: ClosedRange<Double>
    let muscularity: ClosedRange<Double>
    let proportion: ClosedRange<Double>

    static let unit = BodyParameterRanges(adiposity: 0...1, muscularity: 0...1, proportion: 0...1)
}

/// A calculation with lineage, deliberately without an evidence or observation id.
struct BodyParameterDerivedFFMI: Codable, Equatable, Sendable {
    let value: Double
    let lineageIds: [String]
}

/// Codable derived presentation only. Source observations retain their own dates
/// and identities; reconstructing with another model does not create an observation.
struct BodyParameterPresentation: Codable, Equatable, Sendable {
    let family: BodyParameterFamily
    let parameters: BodyParameterValues
    let reconstructionModelId: String
    let reconstructionModelVersion: String
    let evidenceLinks: [VisualizationEvidenceLink]
    let derivedFFMI: BodyParameterDerivedFFMI?
}

enum BodyParameterModelError: Error, Equatable {
    case invalidModelIdentity
    case nonFiniteParameter
    case unsupportedRange
    case invalidEvidence
    case independentFFMI
}

/// LYB-371: uncalibrated projection, with no physiological mapping to shape.
struct BodyParameterModel: Sendable {
    let id: String
    let version: String

    static let current = BodyParameterModel(id: "lyb.body-parameters.uncalibrated", version: "1.0.0")

    /// A canonical reader may supply narrower supported ranges from height,
    /// weight, DXA, or source estimates. Those inputs never select coordinates.
    /// This layer neither selects sources nor resolves conflicting evidence.
    func project(
        family: BodyParameterFamily,
        requested: BodyParameterValues,
        supportedRanges: BodyParameterRanges = .unit,
        evidence: [CanonicalBodyEvidenceRef] = []
    ) throws -> BodyParameterPresentation {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BodyParameterModelError.invalidModelIdentity
        }
        guard !evidence.contains(where: { $0.role == .ffmi }) else {
            throw BodyParameterModelError.independentFFMI
        }
        guard Set(evidence.map(\.accountId)).count <= 1,
              Set(evidence.map(\.id)).count == evidence.count else {
            throw BodyParameterModelError.invalidEvidence
        }
        let parameters = try BodyParameterValues(
            adiposity: clamp(requested.adiposity, to: supportedRanges.adiposity),
            muscularity: clamp(requested.muscularity, to: supportedRanges.muscularity),
            proportion: clamp(requested.proportion, to: supportedRanges.proportion)
        )
        return BodyParameterPresentation(
            family: family,
            parameters: parameters,
            reconstructionModelId: id,
            reconstructionModelVersion: version,
            evidenceLinks: evidence.map(link).sorted { $0.id < $1.id },
            derivedFFMI: derivedFFMI(evidence)
        )
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) throws -> Double {
        guard value.isFinite else { throw BodyParameterModelError.nonFiniteParameter }
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound >= 0, range.upperBound <= 1 else {
            throw BodyParameterModelError.unsupportedRange
        }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private func derivedFFMI(_ evidence: [CanonicalBodyEvidenceRef]) -> BodyParameterDerivedFFMI? {
        guard let height = single(.height, unit: "cm", in: evidence),
              let weight = single(.weight, unit: "kg", in: evidence),
              let bodyFat = single(.bodyFat, unit: "%", in: evidence),
              let heightCm = height.magnitude, let weightKg = weight.magnitude,
              let percent = bodyFat.magnitude,
              let value = UnitConversion.calculateFFMI(
                weightKg: weightKg, bodyFatPercentage: percent, heightCm: heightCm
              ), value.isFinite else { return nil }
        return BodyParameterDerivedFFMI(value: value, lineageIds: [height.id, weight.id, bodyFat.id].sorted())
    }

    private func single(
        _ role: CanonicalBodyEvidenceRef.Role,
        unit: String,
        in evidence: [CanonicalBodyEvidenceRef]
    ) -> CanonicalBodyEvidenceRef? {
        let candidates = evidence.filter { $0.role == role }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.unit == unit, candidate.magnitude?.isFinite == true,
              candidate.conflictIds.isEmpty, !candidate.stale else { return nil }
        return candidate
    }

    private func link(_ evidence: CanonicalBodyEvidenceRef) -> VisualizationEvidenceLink {
        VisualizationEvidenceLink(
            id: evidence.id,
            role: evidence.role,
            recordKind: evidence.recordKind,
            epistemic: evidence.epistemic,
            sourceDefinition: evidence.sourceDefinition,
            stale: evidence.stale,
            conflictIds: evidence.conflictIds,
            lineageIds: evidence.lineageIds,
            rawObservationIds: evidence.rawObservationIds
        )
    }
}
