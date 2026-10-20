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
    let scanWeight: Double?
    let scanWeightUnit: String?
    let bodyFatPercentage: Double?
    let muscleMass: Double?
    let boneMass: Double?
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
        case scanWeight = "scan_weight"
        case scanWeightUnit = "scan_weight_unit"
        case bodyFatPercentage = "body_fat_percentage"
        case muscleMass = "muscle_mass"
        case boneMass = "bone_mass"
        case resultPdfUrl = "result_pdf_url"
        case resultPdfName = "result_pdf_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        userId: String,
        bodyMetricsId: String?,
        externalSource: String,
        externalResultId: String,
        externalUpdateTime: Date?,
        scannerModel: String?,
        locationId: String?,
        locationName: String?,
        acquireTime: Date?,
        analyzeTime: Date?,
        vatMassKg: Double?,
        vatVolumeCm3: Double?,
        scanWeight: Double? = nil,
        scanWeightUnit: String? = nil,
        bodyFatPercentage: Double? = nil,
        muscleMass: Double? = nil,
        boneMass: Double? = nil,
        resultPdfUrl: String?,
        resultPdfName: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.bodyMetricsId = bodyMetricsId
        self.externalSource = externalSource
        self.externalResultId = externalResultId
        self.externalUpdateTime = externalUpdateTime
        self.scannerModel = scannerModel
        self.locationId = locationId
        self.locationName = locationName
        self.acquireTime = acquireTime
        self.analyzeTime = analyzeTime
        self.vatMassKg = vatMassKg
        self.vatVolumeCm3 = vatVolumeCm3
        self.scanWeight = scanWeight
        self.scanWeightUnit = scanWeightUnit
        self.bodyFatPercentage = bodyFatPercentage
        self.muscleMass = muscleMass
        self.boneMass = boneMass
        self.resultPdfUrl = resultPdfUrl
        self.resultPdfName = resultPdfName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
