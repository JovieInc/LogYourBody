import AVFoundation
import Foundation
import Observation
import Speech

enum VoiceCaptureError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case unavailable
    case emptyTranscript
    case interrupted

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is off. Enable it in Settings to use Talk."
        case .speechDenied:
            "Speech recognition is off. Enable it in Settings to use Talk."
        case .unavailable:
            "Voice input is unavailable right now. Try again."
        case .emptyTranscript:
            "Nothing heard. Try again."
        case .interrupted:
            "Recording was interrupted. Try again."
        }
    }
}

@MainActor
@Observable
final class VoiceCaptureService {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    private(set) var isRecording = false
    private(set) var isFinishing = false
    private(set) var transcriptPreview = ""

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    func start() async throws {
        guard !isRecording, !isFinishing else { return }
        try await requestPermissions()
        guard let recognizer, recognizer.isAvailable else { throw VoiceCaptureError.unavailable }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceCaptureError.unavailable
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceCaptureError.unavailable
        }

        transcriptPreview = ""
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = recognitionRequest
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        isRecording = true
        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcriptPreview = result.bestTranscription.formattedString
                    if result.isFinal { self.finishWithTranscript() }
                }
                if error != nil, self.finishContinuation != nil {
                    self.finishWithError(VoiceCaptureError.interrupted)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cancel()
            throw VoiceCaptureError.unavailable
        }
    }

    func finish() async throws -> String {
        guard isRecording, let request else { throw VoiceCaptureError.interrupted }
        isRecording = false
        isFinishing = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            request.endAudio()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.finishWithTranscript()
            }
        }
    }

    func cancel() {
        isRecording = false
        isFinishing = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if let finishContinuation {
            self.finishContinuation = nil
            finishContinuation.resume(throwing: CancellationError())
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw VoiceCaptureError.microphoneDenied
        }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else { throw VoiceCaptureError.speechDenied }
    }

    private func finishWithTranscript() {
        guard let finishContinuation else { return }
        self.finishContinuation = nil
        isFinishing = false
        timeoutTask?.cancel()
        timeoutTask = nil
        let transcript = transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard !transcript.isEmpty else {
            finishContinuation.resume(throwing: VoiceCaptureError.emptyTranscript)
            return
        }
        finishContinuation.resume(returning: transcript)
    }

    private func finishWithError(_ error: Error) {
        guard let finishContinuation else { return }
        self.finishContinuation = nil
        isFinishing = false
        timeoutTask?.cancel()
        timeoutTask = nil
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        finishContinuation.resume(throwing: error)
    }
}

enum VoiceCoachPolicy {
    static let featureGate = "hypertrophy_coach_voice_v1"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(featureGate)
    }
}

struct PendingSpokenReply {
    private(set) var clientMessageId: String?

    mutating func track(clientMessageId: String, shouldSpeakReply: Bool) {
        self.clientMessageId = shouldSpeakReply ? clientMessageId : nil
    }

    func shouldSpeakReply(for clientMessageId: String) -> Bool {
        self.clientMessageId == clientMessageId
    }

    mutating func consumeIfMatching(clientMessageId: String) -> Bool {
        guard self.clientMessageId == clientMessageId else { return false }
        self.clientMessageId = nil
        return true
    }

    mutating func cancel(clientMessageId: String) {
        guard self.clientMessageId == clientMessageId else { return }
        self.clientMessageId = nil
    }
}

struct VoiceSetProposal: Decodable, Equatable {
    let sessionId: String
    let exerciseId: String
    let exerciseName: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
}

struct VoiceIntentResponse: Decodable {
    let version: Int
    let kind: String
    let missingFields: [String]?
    let proposal: VoiceSetProposal?
    let heard: VoiceHeardIntent?
}

struct VoiceHeardIntent: Decodable, Equatable {
    let setNumber: Int?
    let reps: Int
    let loadValue: Double?
    let weightUnit: String?
    let loadKg: Double?
    let rir: Int
}

private struct VoiceIntentRequest: Encodable {
    let transcript: String
    let weightUnit: String
    let session: VoiceIntentSession?
}

private struct VoiceIntentSession: Encodable {
    let id: String
    let exercises: [VoiceIntentExercise]
}

private struct VoiceIntentExercise: Encodable {
    let id: String
    let name: String
}

private struct VoiceSpeakRequest: Encodable {
    let text: String
}

enum VoiceAPIError: LocalizedError {
    case authenticationExpired
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authenticationExpired: "Your session expired. Sign in again to use Talk."
        case .unavailable: "Voice is temporarily unavailable. Try again."
        case .invalidResponse: "The voice response could not be read. Try again."
        }
    }
}

final class URLSessionVoiceService {
    private let urlSession: URLSession
    private let baseURL: URL

    init(urlSession: URLSession = .shared, baseURL: URL? = URL(string: Configuration.apiBaseURL)) {
        self.urlSession = urlSession
        self.baseURL = baseURL ?? URL(string: ProductRegistry.Hosts.api)!
    }

    func parseIntent(
        transcript: String,
        accessToken: String,
        session: TrainingSession?,
        weightUnit: String
    ) async throws -> VoiceIntentResponse {
        let context = session.map { value in
            VoiceIntentSession(
                id: value.id,
                exercises: value.exercises.map { VoiceIntentExercise(id: $0.id, name: $0.name) }
            )
        }
        let request = try makeRequest(
            path: "intent",
            accessToken: accessToken,
            body: VoiceIntentRequest(transcript: transcript, weightUnit: weightUnit, session: context)
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(VoiceIntentResponse.self, from: data)
    }

    func speak(text: String, accessToken: String) async throws -> Data {
        let request = try makeRequest(
            path: "speak",
            accessToken: accessToken,
            body: VoiceSpeakRequest(text: text)
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response)
        return data
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        accessToken: String,
        body: Body
    ) throws -> URLRequest {
        guard let url = URL(string: "/api/auth/mobile/voice/v1/\(path)", relativeTo: baseURL)?.absoluteURL else {
            throw VoiceAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw VoiceAPIError.invalidResponse }
        if response.statusCode == 401 { throw VoiceAPIError.authenticationExpired }
        guard (200...299).contains(response.statusCode) else { throw VoiceAPIError.unavailable }
    }
}

enum VoiceSetLogRejection: LocalizedError, Equatable {
    case outsideEngineSession

    var errorDescription: String? { VoiceSetAdmission.rejectedLogMessage }
}

enum VoiceSetAdmission {
    static let rejectedLogMessage = "That set does not match the current engine session. Nothing was logged."

    enum Route: Equatable {
        case confirm(VoiceSetProposal)
        case review(VoiceHeardIntent)
        case clarify(fields: [String], rejected: Bool)
    }

    static func admits(_ proposal: VoiceSetProposal, session: TrainingSession?) -> Bool {
        guard let session, proposal.sessionId == session.id else { return false }
        guard let exercise = session.exercises.first(where: { $0.id == proposal.exerciseId }) else { return false }
        guard exercise.name == proposal.exerciseName else { return false }
        guard (1...max(1, exercise.sets)).contains(proposal.setNumber) else { return false }
        guard (1...50).contains(proposal.reps), (0...6).contains(proposal.rir) else { return false }
        if let loadKg = proposal.loadKg {
            guard loadKg.isFinite, (0...500).contains(loadKg) else { return false }
        }
        return true
    }

    static func route(
        proposal: VoiceSetProposal?,
        heard: VoiceHeardIntent?,
        missingFields: [String]?,
        session: TrainingSession?
    ) -> Route {
        let fields = missingFields ?? []
        if let proposal, fields.isEmpty {
            return admits(proposal, session: session)
                ? .confirm(proposal)
                : .clarify(fields: [], rejected: true)
        }
        if let session,
           !session.exercises.isEmpty,
           let heard,
           !fields.isEmpty,
           fields.allSatisfy(isExerciseOrSetField),
           admitsHeard(heard) {
            return .review(heard)
        }
        if let heard, !fields.isEmpty, fields.allSatisfy(isExerciseOrSetField), !admitsHeard(heard) {
            return .clarify(fields: [], rejected: true)
        }
        return .clarify(fields: fields, rejected: false)
    }

    private static func admitsHeard(_ heard: VoiceHeardIntent) -> Bool {
        guard (1...50).contains(heard.reps), (0...6).contains(heard.rir) else { return false }
        if let loadKg = heard.loadKg {
            guard loadKg.isFinite, (0...500).contains(loadKg) else { return false }
        }
        return true
    }

    private static func isExerciseOrSetField(_ field: String) -> Bool {
        field == "exercise" || field == "set_number"
    }
}

enum VoiceSetLogger {
    static func commit(
        _ proposal: VoiceSetProposal,
        isConfirmed: Bool,
        accessToken: String,
        session: TrainingSession?,
        logSet: (String, TrainingSetLogRequest) async throws -> Void
    ) async throws {
        guard isConfirmed else { return }
        guard VoiceSetAdmission.admits(proposal, session: session) else {
            throw VoiceSetLogRejection.outsideEngineSession
        }
        try await logSet(
            accessToken,
            TrainingSetLogRequest(
                sessionId: proposal.sessionId,
                exerciseId: proposal.exerciseId,
                setNumber: proposal.setNumber,
                reps: proposal.reps,
                loadKg: proposal.loadKg,
                rir: proposal.rir
            )
        )
    }
}

@MainActor
final class VoicePlaybackService {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func play(_ audio: Data) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        player = try AVAudioPlayer(data: audio)
        player?.play()
    }

    func speakOffline(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
