import Foundation
import HealthKit

/// Weight, body fat, and steps each keep their own HealthKit query cursor.
enum HealthAnchorSampleKind: String, CaseIterable, Equatable {
    case weight
    case bodyFat
    case steps

    var defaultsKey: HealthKitDefaultsKey {
        switch self {
        case .weight: return .weightQueryAnchor
        case .bodyFat: return .bodyFatQueryAnchor
        case .steps: return .stepQueryAnchor
        }
    }
}

struct HealthAnchoredSample: Equatable {
    let id: String
    let kind: HealthAnchorSampleKind
    let value: Double
    let date: Date
    let sourceMetadata: BodyMetricSourceMetadata?
}

struct HealthAnchoredDeletion: Equatable {
    let id: String
    let kind: HealthAnchorSampleKind
    /// Set when the deleted sample's day is still known. HealthKit deletions often omit it.
    let date: Date?
}

struct HealthAnchoredSamplePage: Equatable {
    let added: [HealthAnchoredSample]
    let deleted: [HealthAnchoredDeletion]
    let newAnchor: Data?

    static let empty = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: nil)
}

/// One archived `HKQueryAnchor` per sample kind, scoped with `HealthKitDefaultsKey.scoped(with:)`.
struct HealthAnchorStore {
    let defaults: UserDefaults

    func anchor(for kind: HealthAnchorSampleKind, userId: String?) -> Data? {
        defaults.data(forKey: kind.defaultsKey.scoped(with: userId))
    }

    /// The cursor moves only after the import commit succeeds. A failed commit keeps the previous cursor.
    func advance(
        _ anchor: Data?, for kind: HealthAnchorSampleKind, userId: String?, commitSucceeded: Bool
    ) {
        guard commitSucceeded, let anchor, !anchor.isEmpty else { return }
        defaults.set(anchor, forKey: kind.defaultsKey.scoped(with: userId))
    }

    func reset(userId: String?) {
        for kind in HealthAnchorSampleKind.allCases {
            defaults.removeObject(forKey: kind.defaultsKey.scoped(with: userId))
        }
    }

    func hasBodyMetricAnchors(userId: String?) -> Bool {
        anchor(for: .weight, userId: userId) != nil && anchor(for: .bodyFat, userId: userId) != nil
    }
}

struct HealthAnchorImportedRow: Equatable {
    let id: String
    let dataSource: String
    let weight: Double?
    let bodyFatPercentage: Double?
    let metadata: BodyMetricSourceMetadata?
}

enum HealthAnchorRowChange: Equatable {
    case markDeleted(String)
    case keepBodyFatOnly(String, BodyMetricSourceMetadata)
    case keepWeightOnly(String, BodyMetricSourceMetadata)
}

/// Match a deleted HealthKit sample to the imported row by the source-contract sample ids.
enum HealthAnchorDeletionPolicy {
    static func changes(
        deleting sampleId: String, kind: HealthAnchorSampleKind, rows: [HealthAnchorImportedRow]
    ) -> [HealthAnchorRowChange] {
        let deletedId = sampleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deletedId.isEmpty, kind == .weight || kind == .bodyFat else { return [] }
        return rows.compactMap { row in
            guard BodyMetricSource.normalizedRawValue(row.dataSource) == BodyMetricSource.healthKit.rawValue else {
                return nil
            }
            let identities = HealthKitSmartScaleSyncPolicy.recordedIdentities(metadata: row.metadata)
            switch kind {
            case .weight:
                guard identities.weight == deletedId else { return nil }
                if let bodyFatId = identities.bodyFat, bodyFatId != deletedId {
                    return .keepBodyFatOnly(row.id, bodyFatMetadata(row.metadata, sampleId: bodyFatId))
                }
                return .markDeleted(row.id)
            case .bodyFat:
                guard identities.bodyFat == deletedId else { return nil }
                if let weightId = identities.weight, weightId != deletedId, (row.weight ?? 0) > 0 {
                    return .keepWeightOnly(row.id, weightMetadata(row.metadata, sampleId: weightId))
                }
                return .markDeleted(row.id)
            case .steps:
                return nil
            }
        }
    }

    private static func weightMetadata(
        _ metadata: BodyMetricSourceMetadata?, sampleId: String
    ) -> BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: metadata?.vendor ?? "apple_health",
            sourceName: metadata?.sourceName,
            sourceBundleId: metadata?.sourceBundleId,
            deviceId: metadata?.deviceId,
            deviceManufacturer: metadata?.deviceManufacturer,
            deviceModel: metadata?.deviceModel,
            sampleId: sampleId,
            quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
        )
    }

    private static func bodyFatMetadata(
        _ metadata: BodyMetricSourceMetadata?, sampleId: String
    ) -> BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: metadata?.vendor ?? "apple_health",
            sourceName: metadata?.sourceName,
            sourceBundleId: metadata?.sourceBundleId,
            deviceId: metadata?.deviceId,
            deviceManufacturer: metadata?.deviceManufacturer,
            deviceModel: metadata?.deviceModel,
            sampleId: sampleId,
            quantityType: HKQuantityTypeIdentifier.bodyFatPercentage.rawValue
        )
    }
}
