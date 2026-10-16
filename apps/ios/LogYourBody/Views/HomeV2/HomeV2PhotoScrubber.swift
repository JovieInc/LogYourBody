import SwiftUI
import UIKit.UIGestureRecognizerSubclass

enum HomeV2PhotoScrubPolicy {
    static let holdDuration: TimeInterval = 1.1
    static let gateKey = "home_v2_photo_hold_scrub"
    static let fixtureArgument = "-lybUITestPhotoHoldScrub"

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        checkGate: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument) { return true }
        #endif
        let check = checkGate ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }

    static func position(start: Int, translation: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 1, (0..<count).contains(start), width.isFinite, width > 0,
              translation.isFinite else { return nil }
        let delta = min(max(translation / width, -1), 1) * CGFloat(count - 1)
        return Int(min(max(CGFloat(start) + delta, 0), CGFloat(count - 1)).rounded())
    }
}

/// Keeps the recognizer alive while paging gives way to a single scrubbed card.
/// Selection stays in the existing timeline binding; only the mode is transient.
struct HomeV2PhotoScrubber<Selection: Hashable, Content: View>: View {
    let values: [Selection] // Oldest first.
    @Binding var selection: Selection
    let width: CGFloat
    let canActivate: Bool
    var isNavigating = false
    let identifier: String
    @ViewBuilder let content: (Bool) -> Content

    @Environment(\.scenePhase) private var scenePhase
    @State private var isActive = false
    @State private var dragStart: Int?

    private var isAvailable: Bool { values.count > 1 && HomeV2PhotoScrubPolicy.isEnabled() }

    var body: some View {
        ZStack(alignment: .top) {
            content(isActive)
            if isActive {
                Label("Slide through history · Hold to exit", systemImage: "arrow.left.and.right")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                    .foregroundStyle(.white)
                    .padding(HomeV2Tokens.Space.tight)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(HomeV2Tokens.Space.tight)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(identifier + "_scrub_mode")
            }
        }
        .contentShape(Rectangle())
        .gesture(HomeV2PhotoScrubGesture(
            isEnabled: isAvailable && (canActivate || isActive) && !isNavigating,
            isScrubbing: isActive,
            onEvent: handle
        ))
        .accessibilityActions {
            if isAvailable, canActivate || isActive {
                Button(isActive ? "Stop scrubbing history" : "Scrub history", action: toggle)
            }
            if isActive {
                Button("Earlier entry") { adjust(by: -1) }
                Button("Later entry") { adjust(by: 1) }
            }
        }
        .onChange(of: isAvailable) { _, available in if !available { reset() } }
        .onChange(of: isNavigating) { _, navigating in if navigating { reset() } }
        .onChange(of: values) { _, _ in reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { reset() } }
        .onDisappear { reset() }
    }

    private func handle(_ event: HomeV2PhotoScrubRecognizer.Event) {
        switch event {
        case .hold:
            toggle()
            dragStart = values.firstIndex(of: selection)
        case .scrub(let translation):
            guard isActive else { return }
            if dragStart == nil { dragStart = values.firstIndex(of: selection) }
            guard let start = dragStart,
                  let index = HomeV2PhotoScrubPolicy.position(
                    start: start, translation: translation, width: width, count: values.count
                  ), values[index] != selection else { return }
            selection = values[index]
            HapticManager.shared.selection()
        case .end:
            dragStart = nil
        }
    }

    private func toggle() {
        isActive.toggle()
        dragStart = nil
        HapticManager.shared.selection()
    }

    private func adjust(by delta: Int) {
        guard let current = values.firstIndex(of: selection), values.indices.contains(current + delta) else { return }
        selection = values[current + delta]
        HapticManager.shared.selection()
    }

    private func reset() {
        isActive = false
        dragStart = nil
    }
}

private struct HomeV2PhotoScrubGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let isScrubbing: Bool
    let onEvent: (HomeV2PhotoScrubRecognizer.Event) -> Void

    func makeUIGestureRecognizer(context: Context) -> HomeV2PhotoScrubRecognizer {
        let recognizer = HomeV2PhotoScrubRecognizer()
        updateUIGestureRecognizer(recognizer, context: context)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: HomeV2PhotoScrubRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        recognizer.isScrubbing = isScrubbing
    }

    func handleUIGestureRecognizerAction(_ recognizer: HomeV2PhotoScrubRecognizer, context: Context) {
        onEvent(recognizer.event)
    }
}

/// Before activation, moving fails this recognizer so the pager and vertical
/// scroll view retain their gestures. After a hold, the same touch can scrub.
final class HomeV2PhotoScrubRecognizer: UIGestureRecognizer {
    enum Event {
        case hold
        case scrub(CGFloat)
        case end
    }

    var isScrubbing = false
    private(set) var event: Event = .end
    private var origin = CGPoint.zero
    private var timer: Timer?
    private var scrubsAfterHold = false
    private var didHold = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, numberOfTouches == 1 else {
            timer?.invalidate()
            self.event = .end
            state = state == .possible ? .failed : .cancelled
            return
        }
        origin = touch.location(in: view)
        let timer = Timer(timeInterval: HomeV2PhotoScrubPolicy.holdDuration, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible else { return }
            self.didHold = true
            self.scrubsAfterHold = !self.isScrubbing
            self.event = .hold
            self.state = .began
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: view)
        let delta = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        if state == .possible {
            guard hypot(delta.width, delta.height) > 10 else { return }
            timer?.invalidate()
            guard isScrubbing, abs(delta.width) > abs(delta.height) else {
                state = .failed
                return
            }
            self.event = .scrub(delta.width)
            state = .began
        } else if state == .began || state == .changed {
            guard !didHold || scrubsAfterHold else { return }
            self.event = .scrub(delta.width)
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        timer?.invalidate()
        self.event = .end
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible || state == .began || state == .changed else { return }
        timer?.invalidate()
        self.event = .end
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        timer?.invalidate()
        timer = nil
        didHold = false
        scrubsAfterHold = false
        event = .end
    }
}
