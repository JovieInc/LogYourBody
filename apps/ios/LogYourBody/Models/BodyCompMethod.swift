import Foundation

enum BodyCompMethod: String, Codable, CaseIterable {
    case biaScale = "bia_scale"
    case dexa = "dexa"
    case caliper = "caliper"
    case visualEstimate = "visual_estimate"
    case other = "other"

    static func infer(from bodyFatMethod: String?, dataSource: String?) -> BodyCompMethod {
        let normalized = bodyFatMethod?.lowercased() ?? ""
        let source = dataSource?.lowercased() ?? ""

        if normalized.contains("dexa") || source.contains("bodyspec_dexa") {
            return .dexa
        }

        if normalized.contains("caliper") {
            return .caliper
        }

        if normalized.contains("visual") {
            return .visualEstimate
        }

        if source.contains("healthkit") || source.contains("smart_scale") {
            return .biaScale
        }

        if source.contains("manual") && normalized.isEmpty {
            return .visualEstimate
        }

        return .biaScale
    }
}

enum BodyCompSourceType: String, Codable, CaseIterable {
    case healthKit = "healthkit"
    case manual = "manual"
    case partner = "partner"
    case smartScale = "smart_scale"
    case photo = "photo"
    case unknown = "unknown"

    static func infer(from dataSource: String?) -> BodyCompSourceType {
        guard let source = dataSource?.lowercased() else { return .unknown }

        if source.contains("healthkit") {
            return .healthKit
        }

        if source.contains("smart_scale") {
            return .smartScale
        }

        if source.contains("photo") {
            return .photo
        }

        if source.contains("partner") || source.contains("bodyspec_dexa") {
            return .partner
        }

        if source.contains("manual") || source.contains("user") {
            return .manual
        }

        return .unknown
    }
}
