//
// EditEntrySavePolicy.swift
// LogYourBody
//

import Foundation

enum EditEntrySavePolicy {
    static func canAttemptSave(isSaving: Bool, validationMessage: String?, value: String) -> Bool {
        !isSaving
            && validationMessage == nil
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
