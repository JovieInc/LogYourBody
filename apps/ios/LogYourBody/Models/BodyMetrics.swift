//
// BodyMetrics.swift
// LogYourBody
//
import Foundation

struct BodyMetricSource: Codable, Equatable, Hashable {
    let rawValue: String

    static let manual = BodyMetricSource(rawValue: "manual")
    static let healthKit = BodyMetricSource(rawValue: "healthkit")
    static let smartScale = BodyMetricSource(rawValue: "smart_scale")
    static let bodySpecDexa = BodyMetricSource(rawValue: "bodyspec_dexa")
    static let caliper = BodyMetricSource(rawValue: "caliper")
    static let photo = BodyMetricSource(rawValue: "photo")

    static let allowedRawValues: Set<String> = [
        manual.rawValue,
        healthKit.rawValue,
        smartScale.rawValue,
        bodySpecDexa.rawValue,
        caliper.rawValue,
        photo.rawValue
    ]

    init(rawValue: String) {
        self.rawValue = Self.normalizedRawValue(rawValue)
    }

    init(_ rawValue: String?) {
        self.rawValue = Self.normalizedRawValue(rawValue)
    }

    static func normalizedRawValue(_ rawValue: String?) -> String {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") ?? ""

        guard !normalized.isEmpty else {
            return "manual"
        }

        if ["manual", "user", "user_entered", "user_entry"].contains(normalized) {
            return "manual"
        }

        if ["healthkit", "health_kit", "apple_health", "apple_healthkit"].contains(normalized) {
            return "healthkit"
        }

        if [
            "smart_scale",
            "scale",
            "bia_scale",
            "body_scale",
            "connected_scale"
        ].contains(normalized) {
            return "smart_scale"
        }

        if [
            "bodyspec_dexa",
            "bodyspec",
            "partner:bodyspec",
            "partner_bodyspec",
            "dexa",
            "dxa"
        ].contains(normalized) || normalized.contains("bodyspec") {
            return "bodyspec_dexa"
        }

        if normalized.contains("caliper") || normalized.contains("skinfold") {
            return "caliper"
        }

        if ["photo", "photo_import", "progress_photo"].contains(normalized) {
            return "photo"
        }

        return "manual"
    }
}

struct BodyMetricSourceMetadata: Codable, Equatable {
    let vendor: String?
    let sourceName: String?
    let sourceBundleId: String?
    let deviceId: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let sampleId: String?
    let externalId: String?
    let externalResultId: String?
    let scannerModel: String?
    let locationId: String?
    let locationName: String?
    let importedAt: String?
    let legacyDataSource: String?

    init(
        vendor: String? = nil,
        sourceName: String? = nil,
        sourceBundleId: String? = nil,
        deviceId: String? = nil,
        deviceManufacturer: String? = nil,
        deviceModel: String? = nil,
        sampleId: String? = nil,
        externalId: String? = nil,
        externalResultId: String? = nil,
        scannerModel: String? = nil,
        locationId: String? = nil,
        locationName: String? = nil,
        importedAt: String? = nil,
        legacyDataSource: String? = nil
    ) {
        self.vendor = Self.clean(vendor)
        self.sourceName = Self.clean(sourceName)
        self.sourceBundleId = Self.clean(sourceBundleId)
        self.deviceId = Self.clean(deviceId)
        self.deviceManufacturer = Self.clean(deviceManufacturer)
        self.deviceModel = Self.clean(deviceModel)
        self.sampleId = Self.clean(sampleId)
        self.externalId = Self.clean(externalId)
        self.externalResultId = Self.clean(externalResultId)
        self.scannerModel = Self.clean(scannerModel)
        self.locationId = Self.clean(locationId)
        self.locationName = Self.clean(locationName)
        self.importedAt = Self.clean(importedAt)
        self.legacyDataSource = Self.clean(legacyDataSource)
    }

    enum CodingKeys: String, CodingKey {
        case vendor
        case sourceName = "source_name"
        case sourceBundleId = "source_bundle_id"
        case deviceId = "device_id"
        case deviceManufacturer = "device_manufacturer"
        case deviceModel = "device_model"
        case sampleId = "sample_id"
        case externalId = "external_id"
        case externalResultId = "external_result_id"
        case scannerModel = "scanner_model"
        case locationId = "location_id"
        case locationName = "location_name"
        case importedAt = "imported_at"
        case legacyDataSource = "legacy_data_source"
    }

    var isEmpty: Bool {
        jsonObject.isEmpty
    }

    var jsonObject: [String: String] {
        var object: [String: String] = [:]
        object["vendor"] = vendor
        object["source_name"] = sourceName
        object["source_bundle_id"] = sourceBundleId
        object["device_id"] = deviceId
        object["device_manufacturer"] = deviceManufacturer
        object["device_model"] = deviceModel
        object["sample_id"] = sampleId
        object["external_id"] = externalId
        object["external_result_id"] = externalResultId
        object["scanner_model"] = scannerModel
        object["location_id"] = locationId
        object["location_name"] = locationName
        object["imported_at"] = importedAt
        object["legacy_data_source"] = legacyDataSource
        return object
    }

    var jsonString: String? {
        let object = jsonObject
        guard !object.isEmpty,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    init?(jsonString: String?) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }

        self = decoded
    }

    init?(jsonObject: Any?) {
        guard let jsonObject, !(jsonObject is NSNull) else {
            return nil
        }

        if let string = jsonObject as? String {
            self.init(jsonString: string)
            return
        }

        guard let dictionary = jsonObject as? [String: Any],
              JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }

        self = decoded
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(256))
    }
}

struct BodyMetrics: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let date: Date
    let weight: Double?
    let weightUnit: String?
    let bodyFatPercentage: Double?
    let bodyFatMethod: String?
    let muscleMass: Double?
    let boneMass: Double?
    let waistCm: Double?
    let hipCm: Double?
    let waistUnit: String?
    let notes: String?
    let photoUrl: String?
    let dataSource: String?
    let sourceMetadata: BodyMetricSourceMetadata?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        userId: String,
        date: Date,
        weight: Double?,
        weightUnit: String?,
        bodyFatPercentage: Double?,
        bodyFatMethod: String?,
        muscleMass: Double?,
        boneMass: Double?,
        waistCm: Double? = nil,
        hipCm: Double? = nil,
        waistUnit: String? = nil,
        notes: String?,
        photoUrl: String?,
        dataSource: String?,
        sourceMetadata: BodyMetricSourceMetadata? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.weight = weight
        self.weightUnit = weightUnit
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyFatMethod = bodyFatMethod
        self.muscleMass = muscleMass
        self.boneMass = boneMass
        self.waistCm = waistCm
        self.hipCm = hipCm
        self.waistUnit = waistUnit
        self.notes = notes
        self.photoUrl = photoUrl
        self.dataSource = BodyMetricSource.normalizedRawValue(dataSource)
        self.sourceMetadata = sourceMetadata?.isEmpty == true ? nil : sourceMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case weight
        case weightUnit = "weight_unit"
        case bodyFatPercentage = "body_fat_percentage"
        case bodyFatMethod = "body_fat_method"
        case muscleMass = "muscle_mass"
        case boneMass = "bone_mass"
        case waistCm = "waist_circumference"
        case hipCm = "hip_circumference"
        case waistUnit = "waist_unit"
        case notes
        case photoUrl = "photo_url"
        case dataSource = "data_source"
        case sourceMetadata = "source_metadata"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var metricSource: BodyMetricSource {
        BodyMetricSource(dataSource)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        date = try container.decode(Date.self, forKey: .date)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        weightUnit = try container.decodeIfPresent(String.self, forKey: .weightUnit)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        bodyFatMethod = try container.decodeIfPresent(String.self, forKey: .bodyFatMethod)
        muscleMass = try container.decodeIfPresent(Double.self, forKey: .muscleMass)
        boneMass = try container.decodeIfPresent(Double.self, forKey: .boneMass)
        waistCm = try container.decodeIfPresent(Double.self, forKey: .waistCm)
        hipCm = try container.decodeIfPresent(Double.self, forKey: .hipCm)
        waistUnit = try container.decodeIfPresent(String.self, forKey: .waistUnit)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        dataSource = BodyMetricSource.normalizedRawValue(
            try container.decodeIfPresent(String.self, forKey: .dataSource)
        )
        sourceMetadata = try container.decodeIfPresent(BodyMetricSourceMetadata.self, forKey: .sourceMetadata)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
