//
//  WireframeAvatarStage.swift
//  LogYourBody
//
//  Home wireframe for a day without a photo. Rotation is user-driven.
//

import SwiftUI

enum WireframeAvatarStorage {
    static let presentation = "lyb.wireframe.presentation"
    static let adiposity = "lyb.wireframe.adiposity"
    static let muscularity = "lyb.wireframe.muscularity"
    static let frame = "lyb.wireframe.frame"
}

enum WireframeAvatarMotion {
    static let dragGain = 0.008
    static let idleSpin = false
    static let animatedDuration = 0.2
    static let yawLimit = Double.pi
    static let frontYaw = 0.0
    static let sideYaw = Double.pi / 2

    static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : animatedDuration
    }

    static func yaw(for action: String) -> Double {
        action == "side" ? sideYaw : frontYaw
    }

    static func applyDrag(yaw: Double, dx: Double, dy: Double) -> Double {
        if abs(dx) > abs(dy) { return yaw }
        return min(yawLimit, max(-yawLimit, yaw + dy * dragGain))
    }

    /// Stored choice only. Profile sex and uploaded images are not inputs.
    static func presentation(stored: String?) -> String {
        stored == "female" ? "female" : "male"
    }
}

enum WireframeAvatarPolicy {
    static let killSwitchKey = "home_wireframe_kill_switch"
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: "home_wireframe_avatar",
        killSwitchKey: killSwitchKey,
        stage: .graduated,
        minimumBuild: nil
    )

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return FeatureReleaseEvaluator.evaluate(
            releaseDescriptor,
            context: FeatureReleaseContext(
                actor: .ordinaryCustomer,
                installedBuild: 1,
                configState: .fresh,
                enableGate: false,
                killSwitch: check(killSwitchKey)
            )
        ).isEnabled
    }
}

/// Illustrative torso drawn inside the existing stage. It does not resize that stage.
struct WireframeAvatarStage: View {
    var topInset: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WireframeAvatarStorage.presentation) private var storedPresentation = "male"
    @AppStorage(WireframeAvatarStorage.adiposity) private var adiposity = 0.5
    @AppStorage(WireframeAvatarStorage.muscularity) private var muscularity = 0.5
    @AppStorage(WireframeAvatarStorage.frame) private var frame = 0.5
    @State private var yaw = 0.0
    @State private var dragYaw = 0.0
    @State private var showsShape = false
    @State private var asset: WireframeAvatarAsset?

    private var presentation: String {
        WireframeAvatarMotion.presentation(stored: storedPresentation)
    }

    var body: some View {
        Group {
            if WireframeAvatarPolicy.isEnabled() {
                stage
            }
        }
    }

    private var stage: some View {
        canvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { controls }
            .task { asset = await WireframeAvatarCache.shared.asset() }
            .simultaneousGesture(drag)
    }

    private var canvas: some View {
        Canvas { context, size in
            let segments = segments(in: size)
            for segment in segments {
                var path = Path()
                path.move(to: CGPoint(x: segment.x1, y: segment.y1))
                path.addLine(to: CGPoint(x: segment.x2, y: segment.y2))
                context.stroke(
                    path,
                    with: .color(HomeV2Tokens.Colors.ink.opacity(segment.opacity)),
                    lineWidth: 1.15
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(turnHint)
        .accessibilityIdentifier("home_wireframe_avatar")
        .accessibilityAction(named: "Reset") { turn("reset") }
        .accessibilityAction(named: "Front") { turn("front") }
        .accessibilityAction(named: "Side") { turn("side") }
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                chip("Male", id: "home_wireframe_presentation_male", selected: presentation == "male") {
                    storedPresentation = "male"
                }
                chip("Female", id: "home_wireframe_presentation_female", selected: presentation == "female") {
                    storedPresentation = "female"
                }
                chip("Front", id: "home_wireframe_front", selected: false) { turn("front") }
                chip("Side", id: "home_wireframe_side", selected: false) { turn("side") }
                chip("Reset", id: "home_wireframe_reset", selected: false) { turn("reset") }
                chip("Shape", id: "home_wireframe_shape", selected: showsShape) { showsShape.toggle() }
            }
            if showsShape {
                sliders
            }
        }
        .padding(.top, topInset)
        .padding(.trailing, 8)
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 2) {
            slider("Adiposity", value: $adiposity, id: "home_wireframe_adiposity")
            slider("Muscularity", value: $muscularity, id: "home_wireframe_muscularity")
            slider("Frame", value: $frame, id: "home_wireframe_frame")
        }
        .frame(width: 188)
        .padding(8)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                yaw = WireframeAvatarMotion.applyDrag(
                    yaw: dragYaw,
                    dx: value.translation.width,
                    dy: value.translation.height
                )
            }
            .onEnded { _ in dragYaw = yaw }
    }

    private var accessibilityLabel: String {
        let body = presentation == "female" ? "female" : "male"
        return "Illustrative \(body) wireframe. Not a body-fat percentage."
    }

    private var turnHint: String {
        if WireframeAvatarMotion.idleSpin {
            return "Spins continuously"
        }
        return "Drag vertically to turn. A horizontal swipe stays with the timeline."
    }

    private func segments(in size: CGSize) -> [WireframeSegment] {
        let vertices: [SIMD3<Double>]
        let wires: [[Int]]
        if let asset {
            let shape = PersonalBodyEngine.appliedIllustration(
                storedAdiposity: adiposity,
                storedMuscularity: muscularity,
                storedFrame: frame,
                photoByteCount: 0
            )
            vertices = WireframeAvatarLibrary.vertices(
                asset: asset,
                presentation: presentation,
                adiposity: shape.adiposity,
                muscularity: shape.muscularity,
                frame: shape.frame
            )
            wires = asset.wires
        } else {
            vertices = WireframeAvatarLibrary.fallbackVertices()
            wires = WireframeAvatarLibrary.fallbackWires()
        }
        return WireframeAvatarLibrary.project(
            vertices: vertices,
            wires: wires,
            yaw: yaw,
            width: size.width,
            height: size.height
        )
    }

    private func turn(_ action: String) {
        let next = WireframeAvatarMotion.yaw(for: action)
        let duration = WireframeAvatarMotion.animationDuration(reduceMotion: reduceMotion)
        if duration == 0 {
            yaw = next
        } else {
            withAnimation(.easeOut(duration: duration)) { yaw = next }
        }
        dragYaw = next
    }

    private func chip(_ title: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .background(
                    selected ? HomeV2Tokens.Colors.ink.opacity(0.16) : Color.black.opacity(0.35),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func slider(_ title: String, value: Binding<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Slider(value: value, in: 0...1)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.2f", value.wrappedValue))
                .accessibilityIdentifier(id)
        }
    }
}
