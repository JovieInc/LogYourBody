//
// BodyMetrics.swift
// LogYourBody
//
import Foundation
import CryptoKit

struct BodyMetricSource: Codable, Equatable, Hashable {
    let rawValue: String

    static let manual = BodyMetricSource(rawValue: "manual")
    static let healthKit = BodyMetricSource(rawValue: "healthkit")
    static let smartScale = BodyMetricSource(rawValue: "smart_scale")
    static let bodySpecDexa = BodyMetricSource(rawValue: "bodyspec_dexa")
    static let dexaPDF = BodyMetricSource(rawValue: "dexa_pdf")
    static let inbodyPDF = BodyMetricSource(rawValue: "inbody_pdf")
    static let pdfImport = BodyMetricSource(rawValue: "pdf_import")
    static let caliper = BodyMetricSource(rawValue: "caliper")
    static let photo = BodyMetricSource(rawValue: "photo")

    static let allowedRawValues: Set<String> = [
        manual.rawValue,
        healthKit.rawValue,
        smartScale.rawValue,
        bodySpecDexa.rawValue,
        dexaPDF.rawValue,
        inbodyPDF.rawValue,
        pdfImport.rawValue,
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

        if normalized == "inbody_pdf" || normalized.contains("inbody") {
            return "inbody_pdf"
        }

        if normalized == "pdf_import" {
            return "pdf_import"
        }

        if normalized == "dexa_pdf" {
            return "dexa_pdf"
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

enum BodyMetricField: String, CaseIterable {
    case weight
    case bodyFat = "body_fat"
}

struct BodyMetricSourceMetadata: Codable, Equatable {
    let vendor: String?
    let sourceName: String?
    let sourceBundleId: String?
    let deviceId: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let sampleId: String?
    let quantityType: String?
    private(set) var bodyFatSampleId: String?
    let externalId: String?
    let externalResultId: String?
    let scannerModel: String?
    let locationId: String?
    let locationName: String?
    let importedAt: String?
    let legacyDataSource: String?
    private var weightEntrySource: String?
    private var bodyFatEntrySource: String?
    private var bodyFatEntryMethod: String?
    private var weightOperationIdStorage: String?
    private var weightRevisionStorage: Int?
    private var extraFields: [String: ReportedMeasurementJSON] = [:]

    var weightOperationId: String? { weightOperationIdStorage }
    var weightRevision: Int? { weightRevisionStorage }

    init(
        vendor: String? = nil,
        sourceName: String? = nil,
        sourceBundleId: String? = nil,
        deviceId: String? = nil,
        deviceManufacturer: String? = nil,
        deviceModel: String? = nil,
        sampleId: String? = nil,
        quantityType: String? = nil,
        bodyFatSampleId: String? = nil,
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
        self.quantityType = Self.clean(quantityType)
        self.bodyFatSampleId = Self.clean(bodyFatSampleId)
        self.externalId = Self.clean(externalId)
        self.externalResultId = Self.clean(externalResultId)
        self.scannerModel = Self.clean(scannerModel)
        self.locationId = Self.clean(locationId)
        self.locationName = Self.clean(locationName)
        self.importedAt = Self.clean(importedAt)
        self.legacyDataSource = Self.clean(legacyDataSource)
        self.weightEntrySource = nil
        self.bodyFatEntrySource = nil
        self.bodyFatEntryMethod = nil
        self.weightOperationIdStorage = nil
        self.weightRevisionStorage = nil
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case vendor
        case sourceName = "source_name"
        case sourceBundleId = "source_bundle_id"
        case deviceId = "device_id"
        case deviceManufacturer = "device_manufacturer"
        case deviceModel = "device_model"
        case sampleId = "sample_id"
        case quantityType = "quantity_type"
        case bodyFatSampleId = "body_fat_sample_id"
        case externalId = "external_id"
        case externalResultId = "external_result_id"
        case scannerModel = "scanner_model"
        case locationId = "location_id"
        case locationName = "location_name"
        case importedAt = "imported_at"
        case legacyDataSource = "legacy_data_source"
        case weightEntrySource = "weight_entry_source"
        case bodyFatEntrySource = "body_fat_entry_source"
        case bodyFatEntryMethod = "body_fat_entry_method"
        case weightOperationId = "weight_operation_id"
        case weightRevision = "weight_revision"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceBundleId = try container.decodeIfPresent(String.self, forKey: .sourceBundleId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        deviceManufacturer = try container.decodeIfPresent(String.self, forKey: .deviceManufacturer)
        deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel)
        sampleId = try container.decodeIfPresent(String.self, forKey: .sampleId)
        quantityType = try container.decodeIfPresent(String.self, forKey: .quantityType)
        bodyFatSampleId = try container.decodeIfPresent(String.self, forKey: .bodyFatSampleId)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        externalResultId = try container.decodeIfPresent(String.self, forKey: .externalResultId)
        scannerModel = try container.decodeIfPresent(String.self, forKey: .scannerModel)
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        importedAt = try container.decodeIfPresent(String.self, forKey: .importedAt)
        legacyDataSource = try container.decodeIfPresent(String.self, forKey: .legacyDataSource)
        weightEntrySource = try container.decodeIfPresent(String.self, forKey: .weightEntrySource)
        bodyFatEntrySource = try container.decodeIfPresent(String.self, forKey: .bodyFatEntrySource)
        bodyFatEntryMethod = try container.decodeIfPresent(String.self, forKey: .bodyFatEntryMethod)
        weightOperationIdStorage = try container.decodeIfPresent(String.self, forKey: .weightOperationId)
        weightRevisionStorage = try container.decodeIfPresent(Int.self, forKey: .weightRevision)
        var budget = 4_096
        let fields = try ReportedMeasurementJSON.decode(from: decoder, depth: 0, budget: &budget).object ?? [:]
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        extraFields = fields.filter { !knownKeys.contains($0.key) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(vendor, forKey: .vendor)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(sourceBundleId, forKey: .sourceBundleId)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(deviceManufacturer, forKey: .deviceManufacturer)
        try container.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try container.encodeIfPresent(sampleId, forKey: .sampleId)
        try container.encodeIfPresent(quantityType, forKey: .quantityType)
        try container.encodeIfPresent(bodyFatSampleId, forKey: .bodyFatSampleId)
        try container.encodeIfPresent(externalId, forKey: .externalId)
        try container.encodeIfPresent(externalResultId, forKey: .externalResultId)
        try container.encodeIfPresent(scannerModel, forKey: .scannerModel)
        try container.encodeIfPresent(locationId, forKey: .locationId)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(importedAt, forKey: .importedAt)
        try container.encodeIfPresent(legacyDataSource, forKey: .legacyDataSource)
        try container.encodeIfPresent(weightEntrySource, forKey: .weightEntrySource)
        try container.encodeIfPresent(bodyFatEntrySource, forKey: .bodyFatEntrySource)
        try container.encodeIfPresent(bodyFatEntryMethod, forKey: .bodyFatEntryMethod)
        try container.encodeIfPresent(weightOperationIdStorage, forKey: .weightOperationId)
        try container.encodeIfPresent(weightRevisionStorage, forKey: .weightRevision)
        var extra = encoder.container(keyedBy: MetadataKey.self)
        for (key, value) in extraFields {
            try extra.encode(value, forKey: MetadataKey(key))
        }
    }

    /// Only an explicit field override changes the displayed attribution.
    func entrySource(for field: BodyMetricField) -> BodyMetricSource? {
        let raw = field == .weight ? weightEntrySource : bodyFatEntrySource
        guard let raw, BodyMetricSource.allowedRawValues.contains(raw) else { return nil }
        return BodyMetricSource(rawValue: raw)
    }

    var enteredBodyFatMethod: String? { bodyFatEntryMethod }

    func settingEntrySource(
        _ source: BodyMetricSource?, fields: Set<BodyMetricField>, bodyFatMethod: String? = nil
    ) -> Self {
        var updated = self
        if fields.contains(.weight) { updated.weightEntrySource = source?.rawValue }
        if fields.contains(.bodyFat) {
            updated.bodyFatEntrySource = source?.rawValue
            updated.bodyFatEntryMethod = source == .manual ? Self.clean(bodyFatMethod) : nil
        }
        return updated
    }

    /// Undo owns the replaced measurements, not newer import or photo metadata.
    func restoringEntrySources(from previous: Self?, fields: Set<BodyMetricField>) -> Self {
        var updated = self
        if fields.contains(.weight) { updated.weightEntrySource = previous?.weightEntrySource }
        if fields.contains(.bodyFat) {
            updated.bodyFatEntrySource = previous?.bodyFatEntrySource
            updated.bodyFatEntryMethod = previous?.bodyFatEntryMethod
        }
        return updated
    }

    private struct MetadataKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    var isEmpty: Bool {
        jsonObject.isEmpty
    }

    var jsonObject: [String: Any] {
        var object = extraFields.mapValues(\.foundationValue)
        object["vendor"] = vendor
        object["source_name"] = sourceName
        object["source_bundle_id"] = sourceBundleId
        object["device_id"] = deviceId
        object["device_manufacturer"] = deviceManufacturer
        object["device_model"] = deviceModel
        object["sample_id"] = sampleId
        object["quantity_type"] = quantityType
        object["body_fat_sample_id"] = bodyFatSampleId
        object["external_id"] = externalId
        object["external_result_id"] = externalResultId
        object["scanner_model"] = scannerModel
        object["location_id"] = locationId
        object["location_name"] = locationName
        object["imported_at"] = importedAt
        object["legacy_data_source"] = legacyDataSource
        object["weight_entry_source"] = weightEntrySource
        object["body_fat_entry_source"] = bodyFatEntrySource
        object["body_fat_entry_method"] = bodyFatEntryMethod
        if let weightOperationIdStorage {
            object["weight_operation_id"] = weightOperationIdStorage
        }
        if let weightRevisionStorage {
            object["weight_revision"] = weightRevisionStorage
        }
        return object
    }

    func settingWeightLifecycle(operationId: String, revision: Int) -> Self {
        var updated = self
        updated.weightOperationIdStorage = Self.clean(operationId)
        updated.weightRevisionStorage = revision
        return updated
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

extension BodyMetricSourceMetadata {
    static func jsonFragment(for value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return value }
        return String(json.dropFirst().dropLast())
    }

    var healthKitContext: [String: String] {
        extraFields["healthkit_context"]?.object?.compactMapValues(\.string) ?? [:]
    }

    func recordingHealthKitContext(_ context: [String: String]) -> Self {
        var updated = self
        if !context.isEmpty {
            updated.extraFields["healthkit_context"] = .objectValue(context.mapValues { .text($0) })
        }
        return updated
    }

    var weeklyPhotoProvenance: WeeklyPhotoProvenance? {
        guard let fields = extraFields[WeeklyPhotoProvenance.storageKey]?.object else { return nil }
        return WeeklyPhotoProvenance(storage: fields.compactMapValues(\.string))
    }

    func recordingWeeklyPhoto(_ provenance: WeeklyPhotoProvenance) -> Self {
        var updated = self
        updated.extraFields[WeeklyPhotoProvenance.storageKey] = .objectValue(
            provenance.storageFields.mapValues { .text($0) }
        )
        return updated
    }

    var healthKitSampleKey: [String]? {
        guard let sampleId, let sourceBundleId else { return nil }
        return [sourceBundleId, sampleId]
    }

    var healthKitSyncKey: [String]? {
        guard let sourceBundleId, let quantityType,
              let identifier = healthKitContext["sync_identifier"], !identifier.isEmpty else { return nil }
        return [sourceBundleId, quantityType, identifier]
    }

    var healthKitSyncVersion: Int { Int(healthKitContext["sync_version"] ?? "") ?? 0 }

    var replacedHealthKitSampleIDs: [String] {
        extraFields["healthkit_replaced_sample_ids"]?.array?.compactMap(\.string) ?? []
    }

    func replacingHealthKitSample(_ previous: Self) -> Self {
        var updated = self
        let retired = Set(previous.replacedHealthKitSampleIDs + [previous.sampleId].compactMap { $0 })
        updated.extraFields["healthkit_replaced_sample_ids"] = .arrayValue(retired.sorted().map { .text($0) })
        return updated
    }

    var pairedHealthKitBodyFat: Self? {
        Self(jsonObject: extraFields["healthkit_body_fat"]?.foundationValue)
    }

    func pairingHealthKitBodyFat(_ metadata: Self) -> Self {
        var updated = self
        // The nested record retains the second sample's source, timezone and edit lineage.
        var fields = metadata.extraFields
        for (key, value) in metadata.jsonObject {
            if let string = value as? String { fields[key] = .text(string) }
        }
        updated.bodyFatSampleId = metadata.sampleId
        updated.extraFields["healthkit_body_fat"] = .objectValue(fields)
        return updated
    }

    func healthKitLocalDate(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = healthKitContext["time_zone"].flatMap(TimeZone.init(identifier:)) ?? .current
        return BodyMetricLocalDate.key(for: date, calendar: calendar)
    }

    func healthKitRecordID(userId: String) -> String? {
        guard let key = healthKitSyncKey ?? healthKitSampleKey else { return nil }
        // A stable cloud ID also deduplicates a fresh local store after reinstall.
        let parts = ["healthkit-v1", userId, healthKitSyncKey == nil ? "sample" : "sync"] + key
        let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let bytes = Array(SHA256.hash(data: Data(canonical.utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
            (bytes[6] & 0x0f) | 0x80, bytes[7], (bytes[8] & 0x3f) | 0x80,
            bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString
    }
}

enum HealthKitImportIdentityPolicy {
    static let gateKey = "healthkit_sample_identity_v1"

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }
}

enum HealthKitImportIdentityError: Error {
    case alreadyRecorded
}

struct BodyMetricLocalDate: Equatable {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return key(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    static func normalized(_ value: String?, fallback date: Date, calendar: Calendar = .current) -> String {
        guard let value else {
            return key(for: date, calendar: calendar)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(trimmed) else {
            return key(for: date, calendar: calendar)
        }

        return trimmed
    }

    static func startOfDay(for localDate: String, calendar: Calendar = .current) -> Date? {
        guard let components = components(from: localDate) else {
            return nil
        }

        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: components.year,
                month: components.month,
                day: components.day
            )
        )
    }

    static func hourKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour], from: date)
        return String(format: "%02d", components.hour ?? 0)
    }

    private static func isValid(_ value: String) -> Bool {
        guard let components = components(from: value) else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let dateComponents = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: components.year,
            month: components.month,
            day: components.day
        )

        guard let date = calendar.date(from: dateComponents) else {
            return false
        }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == components.year &&
            resolved.month == components.month &&
            resolved.day == components.day
    }

    private static func components(from value: String) -> (year: Int, month: Int, day: Int)? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return (year, month, day)
    }

    private static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Required UI provenance, including for legacy imports with incomplete metadata.
/// A nil bundle ID means the upstream source did not supply an application ID.
struct BodyMetricProvenance: Equatable, Sendable {
    let sourceName: String
    let sourceBundleId: String?
    let effectiveDate: Date
    let importedAt: Date

    init(sourceName: String?, sourceBundleId: String?, effectiveDate: Date, importedAt: Date) {
        let name = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundle = sourceBundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown source"
        self.sourceBundleId = bundle.flatMap { $0.isEmpty ? nil : $0 }
        self.effectiveDate = effectiveDate
        self.importedAt = importedAt
    }
}

struct BodyMetrics: Identifiable, Codable, Equatable {
    /// `date` is always the measurement date; creation/import time cannot replace it.
    var effectiveDate: Date { date }

    var provenance: BodyMetricProvenance {
        let formatter = ISO8601DateFormatter()
        let recordedImportDate = sourceMetadata?.importedAt.flatMap { value -> Date? in
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: value)
        }
        let name = sourceMetadata?.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback: String
        switch metricSource {
        case .manual: fallback = "Manual"
        case .healthKit: fallback = "Apple Health"
        case .smartScale: fallback = "Smart scale"
        case .bodySpecDexa: fallback = "BodySpec DEXA"
        case .dexaPDF: fallback = "DEXA PDF"
        case .inbodyPDF: fallback = "InBody PDF"
        case .pdfImport: fallback = "PDF import"
        case .caliper: fallback = "Calipers"
        case .photo: fallback = "Photo"
        default: fallback = "Unknown source"
        }
        return BodyMetricProvenance(
            sourceName: name?.isEmpty == false ? name : fallback,
            sourceBundleId: sourceMetadata?.sourceBundleId,
            effectiveDate: effectiveDate, importedAt: recordedImportDate ?? createdAt
        )
    }

    func measurementSource(for field: BodyMetricField) -> BodyMetricSource {
        if field == .weight && correctedValue?.weight != nil ||
            field == .bodyFat && correctedValue?.bodyFatPercentage != nil { return .manual }
        return sourceMetadata?.entrySource(for: field) ?? metricSource
    }

    /// Keep the imported method in storage; a typed replacement cannot claim it.
    var attributedBodyFatMethod: String? {
        if correctedValue?.bodyFatPercentage != nil { return "manual" }
        return sourceMetadata?.entrySource(for: .bodyFat) == .manual
            ? sourceMetadata?.enteredBodyFatMethod ?? "manual" : bodyFatMethod
    }

    let id: String
    let userId: String
    let date: Date
    let localDate: String
    /// Imported values remain the wire/storage values, even after correction.
    let originalWeight: Double?
    let originalBodyFatPercentage: Double?
    let isExcluded: Bool
    let correctedValue: MetricCorrectedValue?
    var weight: Double? { correctedValue?.weight ?? originalWeight }
    var bodyFatPercentage: Double? { correctedValue?.bodyFatPercentage ?? originalBodyFatPercentage }
    let weightUnit: String?
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
        localDate: String? = nil,
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
        isExcluded: Bool = false,
        correctedValue: MetricCorrectedValue? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.localDate = BodyMetricLocalDate.normalized(localDate, fallback: date)
        self.originalWeight = weight
        self.isExcluded = isExcluded
        self.correctedValue = correctedValue
        self.weightUnit = weightUnit
        self.originalBodyFatPercentage = bodyFatPercentage
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
        case localDate = "local_date"
        case originalWeight = "weight"
        case isExcluded = "is_excluded"
        case correctedValue = "corrected_value"
        case weightUnit = "weight_unit"
        case originalBodyFatPercentage = "body_fat_percentage"
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
        localDate = BodyMetricLocalDate.normalized(
            try container.decodeIfPresent(String.self, forKey: .localDate),
            fallback: date
        )
        originalWeight = try container.decodeIfPresent(Double.self, forKey: .originalWeight)
        isExcluded = try container.decodeIfPresent(Bool.self, forKey: .isExcluded) ?? false
        correctedValue = try container.decodeIfPresent(MetricCorrectedValue.self, forKey: .correctedValue)
        weightUnit = try container.decodeIfPresent(String.self, forKey: .weightUnit)
        originalBodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .originalBodyFatPercentage)
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
