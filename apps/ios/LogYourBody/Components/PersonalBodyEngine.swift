//
//  PersonalBodyEngine.swift
//  LogYourBody
//
//  Optional personal body path for LYB-316. Production stays on the
//  generic wireframe. The weekly photo loop does not gain a step.
//

import Foundation

struct PersonalBodyCandidate: Decodable, Equatable {
    let id: String
    let status: String
    let executed: Bool
}

struct PersonalBodyUnsupported: Decodable, Equatable {
    let omniFlashVerifiedMeshApi: Bool
    let gnmPublicBody: Bool
    let mojuloIsBodyReconstruction: Bool
    let meshlibTimingIsReconstruction: Bool
    let exactRememberedDemoConfirmed: Bool
}

struct PersonalBodyDecision: Decodable, Equatable {
    let issue: String
    let selectedEngineId: String
    let fallbackEngineId: String
    let personalizedProduction: Bool
    let addsCaptureStep: Bool
    let mapsToBodyFat: Bool
    let mapsToDexa: Bool
    let topologyId: String
    let releaseStage: String
    let flagKey: String
    let killSwitchKey: String
    let pose: String
    let crop: String
    let clothing: String
    let candidates: [PersonalBodyCandidate]
    let unsupported: PersonalBodyUnsupported
}

struct PersonalIllustrationChoice: Equatable {
    let adiposity: Double
    let muscularity: Double
    let frame: Double
    let personalized: Bool
    let engineId: String
}

enum PersonalBodyEngine {
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: "personal_body_engine",
        killSwitchKey: "personal_body_engine_kill_switch",
        stage: .disabled,
        minimumBuild: nil
    )

    static func load(from url: URL) -> PersonalBodyDecision? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersonalBodyDecision.self, from: data)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) -> PersonalBodyDecision? {
        guard let url = bundle.url(forResource: "PersonalBodyEngine", withExtension: "json") else {
            return nil
        }
        return load(from: url)
    }

    static func isPersonalizationEnabled(
        descriptor: FeatureReleaseDescriptor = releaseDescriptor,
        context: FeatureReleaseContext = FeatureReleaseContext(
            actor: .ordinaryCustomer,
            installedBuild: 1,
            configState: .fresh,
            enableGate: true,
            killSwitch: false
        )
    ) -> Bool {
        FeatureReleaseEvaluator.evaluate(descriptor, context: context).isEnabled
    }

    /// Stored sliders remain the drawing. Photo bytes and mixed body states
    /// cannot turn a personal mesh on.
    static func appliedIllustration(
        storedAdiposity: Double,
        storedMuscularity: Double,
        storedFrame: Double,
        photoByteCount: Int = 0,
        bodyStates: [String] = [],
        decision: PersonalBodyDecision? = nil,
        personalizationEnabled: Bool? = nil
    ) -> PersonalIllustrationChoice {
        let enabled = personalizationEnabled ?? isPersonalizationEnabled()
        let mixedBodyState = Set(bodyStates).count > 1
        // The disabled stage returns before any decision file is read.
        guard enabled, photoByteCount == 0, !mixedBodyState else {
            return PersonalIllustrationChoice(
                adiposity: storedAdiposity,
                muscularity: storedMuscularity,
                frame: storedFrame,
                personalized: false,
                engineId: decision?.fallbackEngineId ?? "lyb.wireframe.torso"
            )
        }
        let resolved = decision ?? loadFromBundle()
        let fallback = resolved?.fallbackEngineId ?? "lyb.wireframe.torso"
        let allowed = resolved?.personalizedProduction == true
        return PersonalIllustrationChoice(
            adiposity: storedAdiposity,
            muscularity: storedMuscularity,
            frame: storedFrame,
            personalized: allowed,
            engineId: allowed ? (resolved?.selectedEngineId ?? fallback) : fallback
        )
    }
}
