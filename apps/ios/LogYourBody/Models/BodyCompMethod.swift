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

        if normalized.contains("dexa") {
            return .dexa
        }

        if normalized.contains("caliper") {
            return .caliper
        }

        if normalized.contains("visual") {
            return .visualEstimate
        }

        if source.contains("healthkit") {
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
    case unknown = "unknown"

    static func infer(from dataSource: String?) -> BodyCompSourceType {
        guard let source = dataSource?.lowercased() else { return .unknown }

        if source.contains("healthkit") {
            return .healthKit
        }

        if source.contains("partner") {
            return .partner
        }

        if source.contains("manual") || source.contains("user") {
            return .manual
        }

        return .unknown
    }
}
