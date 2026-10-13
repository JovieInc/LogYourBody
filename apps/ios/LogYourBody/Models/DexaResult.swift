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
    let reportedMeasurements: ReportedMeasurements?
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
        case reportedMeasurements = "reported_measurements"
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
        reportedMeasurements: ReportedMeasurements? = nil,
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
        self.reportedMeasurements = reportedMeasurements
        self.resultPdfUrl = resultPdfUrl
        self.resultPdfName = resultPdfName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        bodyMetricsId = try container.decodeIfPresent(String.self, forKey: .bodyMetricsId)
        externalSource = try container.decode(String.self, forKey: .externalSource)
        externalResultId = try container.decode(String.self, forKey: .externalResultId)
        externalUpdateTime = try container.decodeIfPresent(Date.self, forKey: .externalUpdateTime)
        scannerModel = try container.decodeIfPresent(String.self, forKey: .scannerModel)
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        acquireTime = try container.decodeIfPresent(Date.self, forKey: .acquireTime)
        analyzeTime = try container.decodeIfPresent(Date.self, forKey: .analyzeTime)
        vatMassKg = try container.decodeIfPresent(Double.self, forKey: .vatMassKg)
        vatVolumeCm3 = try container.decodeIfPresent(Double.self, forKey: .vatVolumeCm3)
        scanWeight = try container.decodeIfPresent(Double.self, forKey: .scanWeight)
        scanWeightUnit = try container.decodeIfPresent(String.self, forKey: .scanWeightUnit)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        muscleMass = try container.decodeIfPresent(Double.self, forKey: .muscleMass)
        boneMass = try container.decodeIfPresent(Double.self, forKey: .boneMass)
        resultPdfUrl = try container.decodeIfPresent(String.self, forKey: .resultPdfUrl)
        resultPdfName = try container.decodeIfPresent(String.self, forKey: .resultPdfName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // A malformed optional envelope must not discard the rest of scan history.
        // Nil also means "preserve existing" when this legacy-shaped record is cached.
        reportedMeasurements = try? container.decode(ReportedMeasurements.self, forKey: .reportedMeasurements)
    }
}
