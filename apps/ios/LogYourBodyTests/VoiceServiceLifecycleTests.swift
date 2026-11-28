import AVFoundation
import XCTest
@testable import LogYourBody

@MainActor
final class VoiceServiceLifecycleTests: XCTestCase {
    func testRepeatedIdleCancellationDoesNotCreateAudioEngine() {
        var creations = 0
        let service = VoiceCaptureService(makeAudioEngine: {
            creations += 1
            return AVAudioEngine()
        })
        XCTAssertEqual(creations, 0)
        service.cancel()
        service.cancel()
        XCTAssertEqual(creations, 0, "Leaving text chat must not initialize the microphone's audio engine.")
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isFinishing)
        XCTAssertEqual(service.inputLevel, 0)
        XCTAssertNil(service.recordingStartedAt)
    }

    func testFinishingUnusedCaptureFailsWithoutCreatingAudioEngine() async {
        var creations = 0
        let service = VoiceCaptureService(makeAudioEngine: {
            creations += 1
            return AVAudioEngine()
        })
        do {
            _ = try await service.finish()
            XCTFail("An unused capture cannot produce a transcript.")
        } catch VoiceCaptureError.interrupted {
            XCTAssertFalse(service.isFinishing)
        } catch {
            XCTFail("Unexpected finish error: \(error)")
        }
        service.cancel()
        XCTAssertEqual(creations, 0)
    }

    func testRecreatingUnusedPlaybackDoesNotCreateSpeechSynthesizer() {
        var creations = 0
        for _ in 0..<3 {
            _ = VoicePlaybackService(makeSynthesizer: {
                creations += 1
                return AVSpeechSynthesizer()
            })
        }
        XCTAssertEqual(creations, 0, "Rebuilding text chat must not initialize speech playback.")
    }
}
