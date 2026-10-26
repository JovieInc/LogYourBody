import Foundation
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// Input precision for reported performance, never an engine prescription.
enum TrainingNumericDimension: Equatable {
    case reps
    case load(MeasurementSystem)
    case rir
    // Reserved for the real rest-time binding owned by LYB-116.
    case restSeconds

    static let featureGate = "workout_numeric_scrub_v1"

    var bounds: ClosedRange<Double> {
        switch self {
        case .reps: return 1...50
        case .rir: return 0...6
        case .restSeconds: return 0...3_600
        case .load(let unit): return 0...(unit == .metric ? 500 : UnitConversion.kgToLbs(500))
        }
    }

    var increments: [Double] {
        switch self {
        case .load: return [0.25, 0.5, 1, 1.25, 2.5, 5, 10]
        case .restSeconds: return [5]
        default: return [1]
        }
    }

    var defaultIncrement: Double {
        switch self {
        case .load(.metric): return 0.5
        case .restSeconds: return 5
        default: return 1
        }
    }

    #if canImport(UIKit)
    var keyboard: UIKeyboardType {
        if case .load = self { return .decimalPad }
        return .numberPad
    }
    #endif

    func displayValue(_ canonical: String) -> Double? {
        guard let number = Self.number(canonical) else { return nil }
        if case .load(.imperial) = self { return UnitConversion.kgToLbs(number) }
        return number
    }

    func displayText(_ canonical: String) -> String {
        displayValue(canonical).map(Self.text) ?? canonical
    }

    func canonicalText(_ display: String) -> String? {
        if case .load = self, display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        guard let value = Self.number(display), bounds.contains(value) else { return nil }
        switch self {
        case .load(let unit):
            let kilograms = unit == .metric ? value : UnitConversion.lbsToKg(value)
            return TrainingLoadInputPolicy.savedText(for: kilograms)
        default:
            guard value.rounded() == value else { return nil }
            return String(Int(value))
        }
    }

    func adjusted(_ value: Double, by delta: Double) -> Double {
        let clamped = min(bounds.upperBound, max(bounds.lowerBound, value + delta))
        // Floor the imperial upper endpoint so its displayed value remains <= 500 kg.
        let upper = (bounds.upperBound * 100).rounded(.down) / 100
        return min(upper, (clamped * 100).rounded() / 100)
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$"#, options: .regularExpression) != nil,
              let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite
        else { return nil }
        return value
    }

    static func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// Gesture-only state. No journal, network request, saved-set identity or prescription lives here.
struct TrainingNumericScrubEdit {
    let original: String
    let dimension: TrainingNumericDimension
    let increment: Double
    private let origin: Double
    private var lastTranslation = 0.0
    private var steps = 0.0
    private(set) var value: Double
    private(set) var cancelled = false
    private(set) var fineControl = false

    init?(original: String, dimension: TrainingNumericDimension, increment: Double) {
        guard dimension.increments.contains(increment),
              dimension.canonicalText(dimension.displayText(original)) != nil,
              let value = TrainingNumericDimension.number(dimension.displayText(original.isEmpty ? "0" : original)),
              dimension.bounds.contains(value)
        else { return nil }
        self.original = original
        self.dimension = dimension
        self.increment = increment
        origin = value
        self.value = value
    }

    @discardableResult
    mutating func move(horizontal: Double, vertical: Double) -> Bool {
        guard horizontal.isFinite, vertical.isFinite, !cancelled else { return false }
        if vertical >= 80 { cancelled = true; return false }
        // Lift above the value for fine control; dragging down cancels, including on release.
        fineControl = vertical <= -44
        let pointsPerStep = fineControl ? 48.0 : 12.0
        steps += (horizontal - lastTranslation) / pointsPerStep
        lastTranslation = horizontal
        // Normalize floating-point accumulation so sample frequency cannot lose a step.
        let snappedSteps = ((steps * 1e8).rounded() / 1e8).rounded(.towardZero)
        let next = dimension.adjusted(origin, by: snappedSteps * increment)
        guard next != value else { return false }
        value = next
        return true
    }

    func committedText(current: String) -> String? {
        guard !cancelled, current == original, value != origin else { return nil }
        return dimension.canonicalText(TrainingNumericDimension.text(value))
    }
}

#if canImport(UIKit)
struct TrainingNumericScrub: View {
    let title: String
    @Binding var text: String
    let dimension: TrainingNumericDimension
    let identifier: String

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @State private var edit: TrainingNumericScrubEdit?
    @State private var selectedIncrement: Double?
    @State private var keyboardPresented = false

    private var increment: Double { selectedIncrement ?? dimension.defaultIncrement }
    private var displayed: String {
        if let edit, !edit.cancelled { return TrainingNumericDimension.text(edit.value) }
        return dimension.displayText(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(theme.colors.textSecondary)
            // The readout is above the touch target, leaving it visible under a thumb.
            Text(edit == nil ? "Drag to adjust" : edit?.cancelled == true ? "Cancelled" :
                 edit?.fineControl == true ? "Fine · \(displayed)" : displayed)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
            valueControl
            HStack(spacing: 8) {
                adjustmentButton("minus", delta: -increment)
                Spacer(minLength: 0)
                adjustmentButton("plus", delta: increment)
            }
            if case .load = dimension {
                Menu {
                    ForEach(dimension.increments, id: \.self) { step in
                        Button(TrainingNumericDimension.text(step)) { selectedIncrement = step }
                    }
                } label: {
                    Text("Step: \(TrainingNumericDimension.text(increment))")
                        .font(.caption)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Equipment load increment")
                .accessibilityIdentifier(identifier + "_increment")
            }
        }
        .sheet(isPresented: $keyboardPresented) {
            TrainingNumericEntry(title: title, text: $text, dimension: dimension, identifier: identifier)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { edit = nil; keyboardPresented = false }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { edit = nil; keyboardPresented = false }
        }
        .onChange(of: text) { _, _ in edit = nil }
        .onChange(of: dimension) { _, _ in edit = nil; selectedIncrement = nil; keyboardPresented = false }
        .onChange(of: selectedIncrement) { _, _ in edit = nil }
        .onDisappear { edit = nil }
    }

    private var valueControl: some View {
        Text(displayed.isEmpty ? "—" : displayed)
            .font(.title2.monospacedDigit())
            .foregroundStyle(theme.colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                TrainingNumericTouchSurface(enabled: isEnabled, onTap: { keyboardPresented = true },
                                            onPan: handlePan)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(displayed.isEmpty ? "Bodyweight" : displayed)
            .accessibilityHint("Swipe up or down to adjust. Double tap to type. Drag up for fine control, down to cancel.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(by: increment)
                case .decrement: adjust(by: -increment)
                @unknown default: break
                }
            }
            .accessibilityAction { keyboardPresented = true }
            .accessibilityIdentifier(identifier)
    }

    private func adjustmentButton(_ symbol: String, delta: Double) -> some View {
        Button { adjust(by: delta) } label: {
            Image(systemName: symbol).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(delta > 0 ? "Increase" : "Decrease") \(title)")
        .accessibilityIdentifier(identifier + (delta > 0 ? "_plus" : "_minus"))
    }

    private func adjust(by delta: Double) {
        guard isEnabled, let value = dimension.displayValue(text.isEmpty ? "0" : text),
              dimension.bounds.contains(value),
              let result = dimension.canonicalText(TrainingNumericDimension.text(dimension.adjusted(value, by: delta))),
              result != text else { return }
        text = result
        HapticManager.shared.selection()
    }

    private func handlePan(_ state: UIGestureRecognizer.State, _ translation: CGPoint) {
        guard isEnabled, scenePhase == .active else { edit = nil; return }
        switch state {
        case .began:
            edit = TrainingNumericScrubEdit(original: text, dimension: dimension, increment: increment)
        case .changed, .ended:
            if edit?.move(horizontal: Double(translation.x), vertical: Double(translation.y)) == true {
                HapticManager.shared.selection()
            }
            if state == .ended {
                let result = edit?.committedText(current: text)
                edit = nil
                if let result { text = result }
            }
        case .cancelled, .failed: edit = nil
        default: break
        }
    }
}

#if DEBUG
private struct TrainingNumericScrubPreview: View {
    @State private var reps = "10"
    @State private var load = "22.5"
    @State private var rir = "3"
    @State private var rest = "90"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TrainingNumericScrub(title: "Reps", text: $reps, dimension: .reps, identifier: "preview_reps")
                TrainingNumericScrub(title: "Load kg", text: $load, dimension: .load(.metric), identifier: "preview_load")
                TrainingNumericScrub(title: "RIR", text: $rir, dimension: .rir, identifier: "preview_rir")
                // Fixture only; no rest timer is edited until LYB-116 supplies its real binding.
                TrainingNumericScrub(title: "Rest seconds", text: $rest, dimension: .restSeconds, identifier: "preview_rest")
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Workout numeric scrub") { TrainingNumericScrubPreview() }
#Preview("Workout numeric scrub · large type") {
    TrainingNumericScrubPreview().environment(\.dynamicTypeSize, .accessibility3)
}
#endif

private struct TrainingNumericEntry: View {
    let title: String
    @Binding var text: String
    let dimension: TrainingNumericDimension
    let identifier: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var input = ""
    @State private var original = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(title, text: $input)
                    .keyboardType(dimension.keyboard)
                    .focused($focused)
                    .accessibilityIdentifier(identifier + "_entry")
                if dimension.canonicalText(input) == nil {
                    Text("Enter a value from \(TrainingNumericDimension.text(dimension.bounds.lowerBound)) to \(TrainingNumericDimension.text(dimension.bounds.upperBound)).")
                        .foregroundStyle(Color.appWarning)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier(identifier + "_cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if text == original, input != dimension.displayText(original),
                           let canonical = dimension.canonicalText(input) { text = canonical }
                        dismiss()
                    }
                    .disabled(dimension.canonicalText(input) == nil || text != original)
                    .accessibilityIdentifier(identifier + "_done")
                }
            }
        }
        .onAppear { original = text; input = dimension.displayText(text); focused = true }
        .presentationDetents([.medium, .large])
    }
}

/// Directional recognition lets vertical ScrollView gestures win. UIKit cancellation
/// (second touch, system interruption) discards provisional edits without a binding write.
private struct TrainingNumericTouchSurface: UIViewRepresentable {
    let enabled: Bool
    let onTap: () -> Void
    let onPan: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        uiView.isUserInteractionEnabled = enabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TrainingNumericTouchSurface
        init(_ parent: TrainingNumericTouchSurface) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func tap() { parent.onTap() }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            parent.onPan(recognizer.state, recognizer.translation(in: recognizer.view))
        }
    }
}
#endif
