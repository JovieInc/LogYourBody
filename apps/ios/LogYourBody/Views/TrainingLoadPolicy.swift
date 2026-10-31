import Foundation

/// The engine carries last session's final-set load forward on hold and
/// add-reps weeks; the load field starts there, like reps start at the target.
enum TrainingLoadPrefillPolicy {
    static func text(for targetLoadKg: Double?) -> String {
        guard let targetLoadKg, targetLoadKg > 0 else { return "" }
        let rounded = (targetLoadKg * 100).rounded() / 100
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
        return rounded.formatted(style)
    }
}

enum TrainingLoadInputPolicy {
    static let invalidMessage = "Enter a load from 0 to 500 kg, or leave it blank for bodyweight."

    static func loadKg(from text: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.range(of: #"^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$"#, options: .regularExpression) != nil,
              let load = Double(value.replacingOccurrences(of: ",", with: ".")),
              load.isFinite, (0...500).contains(load)
        else { throw InputError.invalidLoad }
        return load
    }

    static func isValid(_ text: String) -> Bool {
        do {
            _ = try loadKg(from: text)
            return true
        } catch {
            return false
        }
    }

    static func savedText(for load: Double?) -> String {
        guard let load else { return "" }
        let text = String(load)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    enum InputError: LocalizedError {
        case invalidLoad
        var errorDescription: String? { TrainingLoadInputPolicy.invalidMessage }
    }
}
