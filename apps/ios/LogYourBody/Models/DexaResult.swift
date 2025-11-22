import Foundation

struct DexaResult: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let bodyMetricsId: String?
    let externalSource: String
    let externalResultId: String
    let externalUpdateTime: Date?
    let scannerModel: String?
    let locationId: String?
    let locationName: String?
    let acquireTime: Date?
    let analyzeTime: Date?
    let vatMassKg: Double?
    let vatVolumeCm3: Double?
    let resultPdfUrl: String?
    let resultPdfName: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case bodyMetricsId = "body_metrics_id"
        case externalSource = "external_source"
        case externalResultId = "external_result_id"
        case externalUpdateTime = "external_update_time"
        case scannerModel = "scanner_model"
        case locationId = "location_id"
        case locationName = "location_name"
        case acquireTime = "acquire_time"
        case analyzeTime = "analyze_time"
        case vatMassKg = "vat_mass_kg"
        case vatVolumeCm3 = "vat_volume_cm3"
        case resultPdfUrl = "result_pdf_url"
        case resultPdfName = "result_pdf_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
