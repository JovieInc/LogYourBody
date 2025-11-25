//
// Glp1Medication.swift
// LogYourBody
//

import Foundation

struct Glp1Medication: Identifiable, Codable {
    let id: String
    let userId: String
    let displayName: String
    let genericName: String?
    let drugClass: String?
    let brand: String?
    let route: String?
    let frequency: String?
    let doseUnit: String?
    let isCompounded: Bool
    let hkIdentifier: String?
    let startedAt: Date
    let endedAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case genericName = "generic_name"
        case drugClass = "drug_class"
        case brand
        case route
        case frequency
        case doseUnit = "dose_unit"
        case isCompounded = "is_compounded"
        case hkIdentifier = "hk_identifier"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Catalog of common GLP-1 and related medications and their typical dose ladders.
// This is used to power fast logging UIs (preset lists + dose wheels).

struct Glp1MedicationDoseConfig {
    let unit: String
    let doses: [Double]
}

struct Glp1MedicationPreset {
    let displayName: String
    let genericName: String
    let brand: String
    let drugClass: String
    let route: String
    let frequency: String
    let doseUnit: String
    let doses: [Double]
    let isCompounded: Bool
    let hkIdentifier: String?
}

enum Glp1MedicationCatalog {
    // Subset of the JSON list focused on common GLP-1 and related injectables.
    // Units are encoded into doseUnit for clarity (e.g. "mg/week", "mg/day", "mcg/day").

    private static let presets: [Glp1MedicationPreset] = [
        // Semaglutide (weekly, weight management)
        Glp1MedicationPreset(
            displayName: "Wegovy",
            genericName: "semaglutide",
            brand: "Wegovy",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [0.25, 0.5, 1.0, 1.7, 2.4],
            isCompounded: false,
            hkIdentifier: "hk.glp1.semaglutide.wegovy.weekly"
        ),
        Glp1MedicationPreset(
            displayName: "Ozempic",
            genericName: "semaglutide",
            brand: "Ozempic",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [0.25, 0.5, 1.0, 2.0],
            isCompounded: false,
            hkIdentifier: "hk.glp1.semaglutide.ozempic.weekly"
        ),
        // Oral semaglutide
        Glp1MedicationPreset(
            displayName: "Rybelsus",
            genericName: "semaglutide",
            brand: "Rybelsus",
            drugClass: "GLP-1 receptor agonist",
            route: "oral",
            frequency: "once daily",
            doseUnit: "mg/day",
            doses: [3, 7, 14],
            isCompounded: false,
            hkIdentifier: "hk.glp1.semaglutide.rybelsus.daily"
        ),
        // Tirzepatide (weekly)
        Glp1MedicationPreset(
            displayName: "Mounjaro",
            genericName: "tirzepatide",
            brand: "Mounjaro",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [2.5, 5, 7.5, 10, 12.5, 15],
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.mounjaro.weekly"
        ),
        Glp1MedicationPreset(
            displayName: "Zepbound",
            genericName: "tirzepatide",
            brand: "Zepbound",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [2.5, 5, 7.5, 10, 12.5, 15],
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.zepbound.weekly"
        ),
        // Liraglutide (daily)
        Glp1MedicationPreset(
            displayName: "Saxenda",
            genericName: "liraglutide",
            brand: "Saxenda",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once daily",
            doseUnit: "mg/day",
            doses: [0.6, 1.2, 1.8, 2.4, 3.0],
            isCompounded: false,
            hkIdentifier: "hk.glp1.liraglutide.saxenda.daily"
        ),
        Glp1MedicationPreset(
            displayName: "Victoza",
            genericName: "liraglutide",
            brand: "Victoza",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once daily",
            doseUnit: "mg/day",
            doses: [0.6, 1.2, 1.8],
            isCompounded: false,
            hkIdentifier: "hk.glp1.liraglutide.victoza.daily"
        ),
        // Dulaglutide (weekly)
        Glp1MedicationPreset(
            displayName: "Trulicity",
            genericName: "dulaglutide",
            brand: "Trulicity",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [0.75, 1.5, 3.0, 4.5],
            isCompounded: false,
            hkIdentifier: "hk.glp1.dulaglutide.trulicity.weekly"
        ),
        // Exenatide
        Glp1MedicationPreset(
            displayName: "Byetta",
            genericName: "exenatide",
            brand: "Byetta",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "twice daily",
            doseUnit: "mcg/dose",
            doses: [5, 10],
            isCompounded: false,
            hkIdentifier: "hk.glp1.exenatide.byetta.bid"
        ),
        Glp1MedicationPreset(
            displayName: "Bydureon BCise",
            genericName: "exenatide",
            brand: "Bydureon BCise",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [2.0],
            isCompounded: false,
            hkIdentifier: "hk.glp1.exenatide.bydureon.weekly"
        ),
        // Lixisenatide
        Glp1MedicationPreset(
            displayName: "Adlyxin",
            genericName: "lixisenatide",
            brand: "Adlyxin",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once daily",
            doseUnit: "mcg/day",
            doses: [10, 20],
            isCompounded: false,
            hkIdentifier: "hk.glp1.lixisenatide.adlyxin.daily"
        ),
        // Compounded semaglutide / tirzepatide (common templates)
        Glp1MedicationPreset(
            displayName: "Compounded semaglutide",
            genericName: "semaglutide (compounded)",
            brand: "Compounded semaglutide",
            drugClass: "GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [0.25, 0.5, 1.0, 1.5, 2.0, 2.5],
            isCompounded: true,
            hkIdentifier: "hk.glp1.semaglutide.compounded.weekly"
        ),
        Glp1MedicationPreset(
            displayName: "Compounded tirzepatide",
            genericName: "tirzepatide (compounded)",
            brand: "Compounded tirzepatide",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            doses: [2.5, 5, 7.5, 10, 12.5, 15],
            isCompounded: true,
            hkIdentifier: "hk.glp1.tirzepatide.compounded.weekly"
        )
    ]

    static var allPresets: [Glp1MedicationPreset] {
        presets
    }

    static func preset(forBrand brand: String) -> Glp1MedicationPreset? {
        presets.first { $0.brand.caseInsensitiveCompare(brand) == .orderedSame }
    }

    static func doseConfig(for medication: Glp1Medication) -> Glp1MedicationDoseConfig {
        if let brand = medication.brand,
           let preset = preset(forBrand: brand) {
            return Glp1MedicationDoseConfig(unit: preset.doseUnit, doses: preset.doses)
        }

        if let generic = medication.genericName?.lowercased() {
            if let preset = presets.first(where: { $0.genericName.lowercased() == generic }) {
                return Glp1MedicationDoseConfig(unit: preset.doseUnit, doses: preset.doses)
            }
        }

        // Fallback: weekly mg ladder
        return Glp1MedicationDoseConfig(
            unit: medication.doseUnit ?? "mg/week",
            doses: [0.25, 0.5, 1.0, 1.5, 2.0, 2.5]
        )
    }
}
