import Foundation

/// Bounded wire data, distinct from the historical untyped muscle scalar.
struct ReportedMeasurements: Codable, Equatable {
    enum Kind: String {
        case leanMass = "lean_mass"
        case fatFreeMass = "fat_free_mass"
        case muscleMass = "muscle_mass"
        case skeletalMuscleMass = "skeletal_muscle_mass"
        case unidentifiedMass = "unidentified_mass"
    }

    enum Unit: String {
        case kilograms = "kg"
        case pounds = "lb"
        case grams = "g"
    }

    struct KnownMeasurement: Equatable {
        let kind: Kind
        let value: Double
        let unit: Unit
        let reportedLabel: String
        let reportedUnit: String?
    }

    private let raw: ReportedMeasurementJSON
    let jsonString: String

    init?(jsonString: String?) {
        guard let jsonString, jsonString.utf8.count <= 16 * 1_024,
              let decoded = try? JSONDecoder().decode(Self.self, from: Data(jsonString.utf8)) else {
            return nil
        }
        self = decoded
    }

    init(from decoder: Decoder) throws {
        var budget = 512
        let value = try ReportedMeasurementJSON.decode(from: decoder, depth: 0, budget: &budget)
        guard Self.isValidEnvelope(value) else {
            throw Self.invalid(decoder, "Invalid reported-measurements envelope")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= 16 * 1_024, let string = String(data: data, encoding: .utf8) else {
            throw Self.invalid(decoder, "Reported measurements exceed the byte limit")
        }
        raw = value
        jsonString = string
    }

    func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }

    var jsonObject: [String: Any] {
        raw.object?.mapValues(\.foundationValue) ?? [:]
    }

    /// Unsupported versions/kinds and unknown units never become interpreted masses.
    var knownMeasurements: [KnownMeasurement] {
        guard raw.object?["schema_version"]?.number == 1,
              let items = raw.object?["items"]?.array else { return [] }
        return items.compactMap { item in
            guard let fields = item.object,
                  let kind = fields["kind"]?.string.flatMap(Kind.init(rawValue:)),
                  let value = fields["value"]?.number,
                  let unit = fields["unit"]?.string.flatMap(Unit.init(rawValue:)),
                  let label = fields["reported_label"]?.string else { return nil }
            return KnownMeasurement(
                kind: kind, value: value, unit: unit, reportedLabel: label,
                reportedUnit: fields["reported_unit"]?.string
            )
        }
    }

    private static func isValidEnvelope(_ raw: ReportedMeasurementJSON) -> Bool {
        guard let fields = raw.object,
              let version = fields["schema_version"]?.number,
              version >= 1, version <= 9_007_199_254_740_991, version.rounded() == version,
              let items = fields["items"]?.array else { return false }
        return items.allSatisfy { item in
            guard let fields = item.object, let kind = fields["kind"]?.string,
                  validLabel(kind, maximum: 80) else { return false }
            guard version == 1, Kind(rawValue: kind) != nil else { return true }
            return validKnownMeasurement(fields)
        }
    }

    private static func validKnownMeasurement(_ fields: [String: ReportedMeasurementJSON]) -> Bool {
        guard let value = fields["value"]?.number, value.isFinite, value > 0,
              let unit = fields["unit"],
              unit == .null || unit.string.flatMap(Unit.init(rawValue:)) != nil,
              let label = fields["reported_label"]?.string, validLabel(label, maximum: 160),
              let reportedUnit = fields["reported_unit"] else { return false }
        return reportedUnit == .null || reportedUnit.string.map { validLabel($0, maximum: 32) } == true
    }

    private static func validLabel(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= maximum
    }

    private static func invalid(_ decoder: Decoder, _ description: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
    }
}

// The interoperable server contract uses finite IEEE-754 numbers. Preserve native
// Int64/UInt64 tokens exactly as well; do not coerce every opaque value to Double.
private indirect enum ReportedMeasurementJSON: Equatable, Encodable {
    case null
    case boolean(Bool)
    case signed(Int64)
    case unsigned(UInt64)
    case floating(Double)
    case text(String)
    case arrayValue([ReportedMeasurementJSON])
    case objectValue([String: ReportedMeasurementJSON])

    var object: [String: ReportedMeasurementJSON]? {
        if case let .objectValue(value) = self { return value }
        return nil
    }

    var array: [ReportedMeasurementJSON]? {
        if case let .arrayValue(value) = self { return value }
        return nil
    }

    var string: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    var number: Double? {
        switch self {
        case let .signed(value): return Double(value)
        case let .unsigned(value): return Double(value)
        case let .floating(value): return value
        default: return nil
        }
    }

    var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case let .boolean(value): return value
        case let .signed(value): return NSNumber(value: value)
        case let .unsigned(value): return NSNumber(value: value)
        case let .floating(value): return NSNumber(value: value)
        case let .text(value): return value
        case let .arrayValue(value): return value.map(\.foundationValue)
        case let .objectValue(value): return value.mapValues(\.foundationValue)
        }
    }

    static func decode(from decoder: Decoder, depth: Int, budget: inout Int) throws -> Self {
        budget -= 1
        guard budget >= 0, depth <= 6 else { throw invalid(decoder) }
        let container = try decoder.singleValueContainer()
        if let scalar = try scalar(from: container) { return scalar }
        if var array = try? decoder.unkeyedContainer() {
            var values: [Self] = []
            while !array.isAtEnd {
                guard values.count < 64 else { throw invalid(decoder) }
                values.append(try decode(from: array.superDecoder(), depth: depth + 1, budget: &budget))
            }
            return .arrayValue(values)
        }
        let object = try decoder.container(keyedBy: Key.self)
        guard object.allKeys.count <= 64 else { throw invalid(decoder) }
        var values: [String: Self] = [:]
        for key in object.allKeys {
            guard key.stringValue.utf16.count <= 160 else { throw invalid(decoder) }
            values[key.stringValue] = try decode(
                from: object.superDecoder(forKey: key), depth: depth + 1, budget: &budget
            )
        }
        return .objectValue(values)
    }

    private static func scalar(from container: SingleValueDecodingContainer) throws -> Self? {
        if container.decodeNil() { return .null }
        if let value = try? container.decode(Bool.self) { return .boolean(value) }
        if let value = try? container.decode(String.self) { return .text(value) }
        if let value = try? container.decode(Int64.self) { return .signed(value) }
        if let value = try? container.decode(UInt64.self) { return .unsigned(value) }
        if let value = try? container.decode(Double.self), value.isFinite { return .floating(value) }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .boolean(value): try container.encode(value)
        case let .signed(value): try container.encode(value)
        case let .unsigned(value): try container.encode(value)
        case let .floating(value): try container.encode(value)
        case let .text(value): try container.encode(value)
        case let .arrayValue(value): try container.encode(value)
        case let .objectValue(value): try container.encode(value)
        }
    }

    private static func invalid(_ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Reported JSON exceeds bounds"))
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
