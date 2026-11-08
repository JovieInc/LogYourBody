import SwiftUI
import UIKit

struct PhotographicAppearanceCanvas: View {
    let display: PhotographicAppearanceDisplay
    @Binding var yaw: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WireframeAvatarStorage.presentation) private var storedPresentation = "male"
    @State private var dragYaw = 0.0
    @State private var asset: WireframeAvatarAsset?

    var body: some View {
        canvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { controls }
            .overlay(alignment: .bottomLeading) { caption }
            .task { asset = await WireframeAvatarCache.shared.asset() }
            .simultaneousGesture(drag)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("photographic_appearance_stage")
    }

    private var canvas: some View {
        Canvas { context, size in
            let region = PhotographicAppearance.visibleRegion(yaw)
            let observed = display.observedRegions.contains(region)
            let tone = display.toneByRegion[region] ?? 0.5
            let color = observed
                ? Color(white: 0.45 + tone * 0.4)
                : HomeV2Tokens.Colors.ink.opacity(0.28)
            for segment in segments(in: size) {
                var path = Path()
                path.move(to: CGPoint(x: segment.x1, y: segment.y1))
                path.addLine(to: CGPoint(x: segment.x2, y: segment.y2))
                context.stroke(path, with: .color(color), lineWidth: observed ? 1.6 : 1.05)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            "Photographic appearance. Observed texture is marked. Unseen surfaces stay unmarked. Not a body-fat measurement."
        )
        .accessibilityValue(display.label)
        .accessibilityHint("Drag vertically to turn. A horizontal swipe stays with the timeline.")
        .accessibilityAction(named: "Front") { turn("front") }
        .accessibilityAction(named: "Side") { turn("side") }
        .accessibilityAction(named: "Reset") { turn("reset") }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            turnChip("Front", "photographic_appearance_front", "front")
            turnChip("Side", "photographic_appearance_side", "side")
            turnChip("Reset", "photographic_appearance_reset", "reset")
        }
        .padding(8)
    }

    private var caption: some View {
        Text(display.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .padding(.horizontal, 8)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .background(Color.black.opacity(0.35), in: Capsule(style: .continuous))
            .padding(8)
            .accessibilityIdentifier("photographic_appearance_evidence")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                yaw = PersonalBodyEstimate.applyDrag(
                    yaw: dragYaw,
                    dx: value.translation.width,
                    dy: value.translation.height
                )
            }
            .onEnded { _ in dragYaw = yaw }
    }

    private func segments(in size: CGSize) -> [WireframeSegment] {
        let presentation = WireframeAvatarMotion.presentation(stored: storedPresentation)
        let vertices: [SIMD3<Double>]
        let wires: [[Int]]
        if let asset, asset.topologyId == PhotographicAppearance.topologyId {
            let resolved = WireframeAvatarLibrary.vertices(
                asset: asset,
                presentation: presentation,
                adiposity: display.shape.adiposity,
                muscularity: display.shape.muscularity,
                frame: display.shape.frame
            )
            let depth = PersonalBodyEstimate.depthScale(display.shape.depth)
            vertices = resolved.map { SIMD3($0.x, $0.y, $0.z * depth) }
            wires = asset.wires
        } else {
            vertices = WireframeAvatarLibrary.fallbackVertices()
            wires = WireframeAvatarLibrary.fallbackWires()
        }
        return WireframeAvatarLibrary.project(
            vertices: vertices, wires: wires, yaw: yaw, width: size.width, height: size.height
        )
    }

    private func turn(_ action: String) {
        let next = PersonalBodyEstimate.yaw(for: action)
        let duration = PhotographicAppearance.motion(reduceMotion: reduceMotion).duration
        if duration == 0 {
            yaw = next
        } else {
            withAnimation(.easeOut(duration: duration)) { yaw = next }
        }
        dragYaw = next
    }

    private func turnChip(_ title: String, _ id: String, _ action: String) -> some View {
        Button { turn(action) } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .padding(.horizontal, 8)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .background(Color.black.opacity(0.35), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
