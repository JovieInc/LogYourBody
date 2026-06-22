import SwiftUI

extension AddEntrySheet {
func deleteGlp1Dose(_ log: Glp1DoseLog) {
        Task {
            let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: log.userId)
            guard deleted else { return }

            if editingGlp1DoseLogId == log.id {
                resetGlp1DoseEditing()
            }

            pendingDeleteGlp1DoseLog = nil
            await loadGlp1DoseLogs(userId: log.userId)
            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
            HapticManager.shared.successAction()
        }
    }

func resetGlp1DoseEditing() {
        editingGlp1DoseLogId = nil
        editingGlp1DoseCreatedAt = nil
        glp1DoseNotes = ""
        glp1IsRestDay = false

        if let medication = glp1SelectedMedication {
            applyDefaultDoseConfig(for: medication)
        } else {
            glp1Dose = ""
            glp1Error = nil
        }
    }

func updateGlp1DoseFromSelection() {
        guard !glp1UseCustomDose else { return }
        let options = glp1DoseOptions

        guard selectedGlp1DoseIndex >= 0,
              selectedGlp1DoseIndex < options.count else { return }

        glp1Dose = String(options[selectedGlp1DoseIndex])
        glp1Error = nil
    }
}
