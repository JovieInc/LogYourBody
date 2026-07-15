//
// Glp1CardAndCatalogTests.swift
// LogYourBodyTests
//
// Coverage for the GLP-1 dashboard card data prep (Glp1DoseCardData) and the
// previously-untested medication catalog lookups (Glp1MedicationCatalog).
//
import XCTest
@testable import LogYourBody

final class Glp1CardAndCatalogTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Glp1DoseCardData.make

    func testCardDataNilForEmptyLogs() {
        XCTAssertNil(Glp1DoseCardData.make(from: []))
    }

    func testCardDataNilWhenNewestLogIsRestDay() {
        // Newest log has no dose -> card is hidden even though an earlier dose exists.
        let logs = [
            makeDoseLog(id: "a", takenAt: base, doseAmount: 2.5),
            makeDoseLog(id: "rest", takenAt: base.addingTimeInterval(86_400), doseAmount: nil)
        ]
        XCTAssertNil(Glp1DoseCardData.make(from: logs))
    }

    func testCardDataUsesNewestLogAfterSorting() throws {
        // Provide out of order; newest by takenAt should headline.
        let logs = [
            makeDoseLog(id: "new", takenAt: base.addingTimeInterval(86_400 * 2), doseAmount: 7.5, unit: "mg/week"),
            makeDoseLog(id: "old", takenAt: base, doseAmount: 2.5, unit: "mg/week")
        ]
        let data = try XCTUnwrap(Glp1DoseCardData.make(from: logs))
        XCTAssertEqual(data.latestDose, 7.5)
        XCTAssertEqual(data.unit, "mg/week")
        XCTAssertEqual(data.latestTakenAt, base.addingTimeInterval(86_400 * 2))
    }

    func testCardDataUnitFallsBackToMg() throws {
        let data = try XCTUnwrap(Glp1DoseCardData.make(from: [
            makeDoseLog(id: "a", takenAt: base, doseAmount: 1.0, unit: nil)
        ]))
        XCTAssertEqual(data.unit, "mg")
    }

    func testCardDataKeepsOnlyLastSevenLogs() throws {
        let logs = (0..<10).map { i in
            makeDoseLog(id: "d\(i)", takenAt: base.addingTimeInterval(Double(i) * 86_400), doseAmount: Double(i))
        }
        let data = try XCTUnwrap(Glp1DoseCardData.make(from: logs))
        XCTAssertEqual(data.dataPoints.count, 7)
        // Indices are re-based 0...6 over the last seven; values are doses 3...9.
        XCTAssertEqual(data.dataPoints.map(\.index), Array(0...6))
        XCTAssertEqual(data.dataPoints.map(\.value), (3...9).map(Double.init))
    }

    func testCardDataRestDayLeavesIndexGapInSparkline() throws {
        // Middle log is a rest day: dropped from points but its index is consumed.
        let logs = [
            makeDoseLog(id: "a", takenAt: base, doseAmount: 1.0),
            makeDoseLog(id: "rest", takenAt: base.addingTimeInterval(86_400), doseAmount: nil),
            makeDoseLog(id: "c", takenAt: base.addingTimeInterval(86_400 * 2), doseAmount: 2.0)
        ]
        let data = try XCTUnwrap(Glp1DoseCardData.make(from: logs))
        XCTAssertEqual(data.dataPoints.map(\.index), [0, 2])
        XCTAssertEqual(data.dataPoints.map(\.value), [1.0, 2.0])
    }

    // MARK: - Glp1MedicationCatalog

    func testPresetLookupIsCaseInsensitive() {
        XCTAssertEqual(Glp1MedicationCatalog.preset(forBrand: "wegovy")?.brand, "Wegovy")
        XCTAssertEqual(Glp1MedicationCatalog.preset(forBrand: "OZEMPIC")?.genericName, "semaglutide")
    }

    func testPresetLookupReturnsNilForUnknownBrand() {
        XCTAssertNil(Glp1MedicationCatalog.preset(forBrand: "NotARealDrug"))
    }

    func testDoseConfigUsesBrandPreset() {
        let med = makeMedication(brand: "Ozempic", genericName: "semaglutide", doseUnit: "mg/week")
        let config = Glp1MedicationCatalog.doseConfig(for: med)
        XCTAssertEqual(config.unit, "mg/week")
        XCTAssertEqual(config.doses, [0.25, 0.5, 1.0, 2.0])
    }

    func testDoseConfigFallsBackToGenericMatch() {
        // No brand match -> first preset whose generic matches (Saxenda for liraglutide).
        let med = makeMedication(brand: nil, genericName: "liraglutide", doseUnit: "mg/day")
        let config = Glp1MedicationCatalog.doseConfig(for: med)
        XCTAssertEqual(config.unit, "mg/day")
        XCTAssertEqual(config.doses, [0.6, 1.2, 1.8, 2.4, 3.0])
    }

    func testDoseConfigFinalFallbackUsesMedicationUnitAndDefaultLadder() {
        let med = makeMedication(brand: nil, genericName: "made-up-peptide", doseUnit: "units/day")
        let config = Glp1MedicationCatalog.doseConfig(for: med)
        XCTAssertEqual(config.unit, "units/day")
        XCTAssertEqual(config.doses, [0.25, 0.5, 1.0, 1.5, 2.0, 2.5])
    }

    func testAllPresetsAreWellFormed() {
        let presets = Glp1MedicationCatalog.allPresets
        XCTAssertFalse(presets.isEmpty)
        for preset in presets {
            XCTAssertFalse(preset.doseUnit.isEmpty, "\(preset.brand) has empty doseUnit")
            XCTAssertFalse(preset.doses.isEmpty, "\(preset.brand) has no doses")
        }
    }

    // MARK: - Glp1DoseDraftResolver

    func testDoseDraftUsesLatestCompatibleDoseForMedicationID() {
        let medication = makeMedication(
            id: "zepbound-current",
            brand: "Zepbound",
            genericName: "tirzepatide",
            doseUnit: "mg/week"
        )
        let draft = Glp1DoseDraftResolver.resolve(
            for: medication,
            doseLogs: [
                makeDoseLog(
                    id: "older",
                    takenAt: base,
                    doseAmount: 2.5,
                    medicationID: medication.id,
                    brand: "Zepbound"
                ),
                makeDoseLog(
                    id: "latest",
                    takenAt: base.addingTimeInterval(86_400),
                    doseAmount: 5,
                    medicationID: medication.id,
                    brand: "Zepbound"
                )
            ]
        )

        XCTAssertEqual(draft.source, .latestLog)
        XCTAssertEqual(draft.doseText, "5")
        XCTAssertEqual(draft.doseUnit, "mg/week")
        XCTAssertEqual(draft.selectedDoseIndex, 1)
        XCTAssertFalse(draft.usesCustomDose)
        XCTAssertEqual(draft.lastLoggedDoseText, "5 mg/week")
    }

    func testDoseDraftUsesCustomValueForDoseOutsideCatalog() {
        let medication = makeMedication(
            id: "zepbound-current",
            brand: "Zepbound",
            genericName: "tirzepatide",
            doseUnit: "mg/week"
        )
        let draft = Glp1DoseDraftResolver.resolve(
            for: medication,
            doseLogs: [
                makeDoseLog(
                    id: "custom",
                    takenAt: base,
                    doseAmount: 6.25,
                    medicationID: medication.id,
                    brand: "Zepbound"
                )
            ]
        )

        XCTAssertEqual(draft.doseText, "6.25")
        XCTAssertNil(draft.selectedDoseIndex)
        XCTAssertTrue(draft.usesCustomDose)
        XCTAssertEqual(draft.lastLoggedDoseText, "6.25 mg/week")
    }

    func testDoseDraftPrefersMedicationIDOverNewerBrandFallback() {
        let medication = makeMedication(
            id: "zepbound-current",
            brand: "Zepbound",
            genericName: "tirzepatide",
            doseUnit: "mg/week"
        )
        let draft = Glp1DoseDraftResolver.resolve(
            for: medication,
            doseLogs: [
                makeDoseLog(
                    id: "current-medication",
                    takenAt: base,
                    doseAmount: 5,
                    medicationID: medication.id,
                    brand: "Zepbound"
                ),
                makeDoseLog(
                    id: "legacy-medication",
                    takenAt: base.addingTimeInterval(86_400),
                    doseAmount: 7.5,
                    medicationID: "previous-zepbound-record",
                    brand: "Zepbound"
                ),
                makeDoseLog(
                    id: "different-medication",
                    takenAt: base.addingTimeInterval(172_800),
                    doseAmount: 2.4,
                    medicationID: "wegovy",
                    brand: "Wegovy"
                )
            ]
        )

        XCTAssertEqual(draft.doseText, "5")
        XCTAssertEqual(draft.selectedDoseIndex, 1)
        XCTAssertEqual(draft.lastLoggedDoseText, "5 mg/week")
    }

    func testDoseDraftFallsBackToMatchingBrandWhenMedicationIDChanged() {
        let medication = makeMedication(
            id: "zepbound-current",
            brand: "Zepbound",
            genericName: "tirzepatide",
            doseUnit: "mg/week"
        )
        let draft = Glp1DoseDraftResolver.resolve(
            for: medication,
            doseLogs: [
                makeDoseLog(
                    id: "legacy-zepbound",
                    takenAt: base,
                    doseAmount: 7.5,
                    medicationID: nil,
                    brand: "Zepbound"
                )
            ]
        )

        XCTAssertEqual(draft.source, .latestLog)
        XCTAssertEqual(draft.doseText, "7.5")
        XCTAssertEqual(draft.selectedDoseIndex, 2)
        XCTAssertFalse(draft.usesCustomDose)
    }

    func testDoseDraftUsesFirstCatalogDoseWhenThereIsNoCompatibleHistory() {
        let medication = makeMedication(
            id: "zepbound-current",
            brand: "Zepbound",
            genericName: "tirzepatide",
            doseUnit: "mg/week"
        )
        let draft = Glp1DoseDraftResolver.resolve(
            for: medication,
            doseLogs: [
                makeDoseLog(
                    id: "other-medication",
                    takenAt: base,
                    doseAmount: 2.4,
                    medicationID: "wegovy",
                    brand: "Wegovy"
                )
            ]
        )

        XCTAssertEqual(draft.source, .catalogDefault)
        XCTAssertEqual(draft.doseText, "2.5")
        XCTAssertEqual(draft.selectedDoseIndex, 0)
        XCTAssertFalse(draft.usesCustomDose)
        XCTAssertNil(draft.lastLoggedDoseText)
    }

    // MARK: - Fixtures

    private func makeDoseLog(
        id: String,
        takenAt: Date,
        doseAmount: Double?,
        unit: String? = "mg/week",
        medicationID: String? = "med",
        brand: String? = "Ozempic"
    ) -> Glp1DoseLog {
        Glp1DoseLog(
            id: id,
            userId: "glp1-card-user",
            takenAt: takenAt,
            medicationId: medicationID,
            doseAmount: doseAmount,
            doseUnit: unit,
            drugClass: "GLP-1 receptor agonist",
            brand: brand,
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: nil,
            createdAt: takenAt,
            updatedAt: takenAt
        )
    }

    private func makeMedication(
        id: String = "med",
        brand: String?,
        genericName: String?,
        doseUnit: String?
    ) -> Glp1Medication {
        Glp1Medication(
            id: id,
            userId: "glp1-card-user",
            displayName: brand ?? "Custom",
            genericName: genericName,
            drugClass: "GLP-1 receptor agonist",
            brand: brand,
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: doseUnit,
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: base,
            endedAt: nil,
            notes: nil,
            createdAt: base,
            updatedAt: base
        )
    }
}
