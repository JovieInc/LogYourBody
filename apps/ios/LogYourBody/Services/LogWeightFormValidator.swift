//
// LogWeightFormValidator.swift
// LogYourBody
//
import Foundation

enum LogWeightInputField {
    case weight
    case bodyFat
}

struct LogWeightFormValidation: Equatable {
    let weightValue: Double?
    let bodyFatValue: Double?
    let weightError: String?
    let bodyFatError: String?
    let formError: String?

    var isValid: Bool {
        formError == nil
            && weightError == nil
            && bodyFatError == nil
            && (weightValue != nil || bodyFatValue != nil)
    }
}

enum LogWeightFormValidator {
    static func validate(weight: String, bodyFat: String, unit: String) -> LogWeightFormValidation {
        var weightValue: Double?
        var bodyFatValue: Double?
        var weightError: String?
        var bodyFatError: String?

        if hasValue(weight) {
            do {
                weightValue = try ValidationService.shared.validateWeight(weight, unit: unit)
            } catch let error as ValidationError {
                weightError = error.errorDescription
            } catch {
                weightError = "Please enter a valid number"
            }
        }

        if hasValue(bodyFat) {
            do {
                bodyFatValue = try ValidationService.shared.validateBodyFat(bodyFat)
            } catch let error as ValidationError {
                bodyFatError = error.errorDescription
            } catch {
                bodyFatError = "Please enter a valid percentage"
            }
        }

        let formError = !hasValue(weight) && !hasValue(bodyFat)
            ? "Please enter at least one measurement"
            : nil

        return LogWeightFormValidation(
            weightValue: weightValue,
            bodyFatValue: bodyFatValue,
            weightError: weightError,
            bodyFatError: bodyFatError,
            formError: formError
        )
    }

    static func fieldError(for value: String, field: LogWeightInputField, unit: String) -> String? {
        guard hasValue(value) else { return nil }

        switch field {
        case .weight:
            return validate(weight: value, bodyFat: "", unit: unit).weightError
        case .bodyFat:
            return validate(weight: "", bodyFat: value, unit: unit).bodyFatError
        }
    }

    private static func hasValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
