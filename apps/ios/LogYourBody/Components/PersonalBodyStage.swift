//
//  PersonalBodyStage.swift
//  LogYourBody
//
//  Estimated outline inside the existing 4:5 stage. Vertical drag turns the
//  body. A horizontal drag stays with the timeline.
//

import SwiftUI

struct PersonalBodyModeControl: View {
    let mode: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            chip("Photo", mode: "photo", id: "personal_body_mode_photo")
            chip("Estimated 3D", mode: "estimate", id: "personal_body_mode_estimate")
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, mode selected: String, id: String) -> some View {
        Button {
            onChange(selected)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .background(
                    mode == selected ? HomeV2Tokens.Colors.ink.opacity(0.16) : Color.black.opacity(0.35),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct PersonalBodyCanvas: View {
    let shape: PersonalBodyShape
    let label: String
    @Binding var yaw: Double
    let scale: Double

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
            .accessibilityIdentifier("personal_body_stage")
    }

    private var canvas: some View {
        Canvas { context, size in
            let segments = segments(in: size)
            for segment in segments {
                var path = Path()
                path.move(to: CGPoint(x: segment.x1, y: segment.y1))
                path.addLine(to: CGPoint(x: segment.x2, y: segment.y2))
                context.stroke(path, with: .color(HomeV2Tokens.Colors.ink.opacity(segment.opacity)), lineWidth: 1.15)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Estimated outline. Not a body-fat measurement.")
        .accessibilityValue(label)
        .accessibilityHint("Drag vertically to turn. A horizontal swipe stays with the timeline.")
        .accessibilityAction(named: "Front") { turn("front") }
        .accessibilityAction(named: "Side") { turn("side") }
        .accessibilityAction(named: "Reset") { turn("reset") }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            turnChip("Front", "personal_body_front", "front")
            turnChip("Side", "personal_body_side", "side")
            turnChip("Reset", "personal_body_reset", "reset")
        }
        .padding(8)
    }

    private var caption: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .padding(.horizontal, 8)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .background(Color.black.opacity(0.35), in: Capsule(style: .continuous))
            .padding(8)
            .accessibilityIdentifier("personal_body_evidence")
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
        if let asset, asset.topologyId == PersonalBodyEstimate.topologyId {
            let resolved = WireframeAvatarLibrary.vertices(
                asset: asset,
                presentation: presentation,
                adiposity: shape.adiposity,
                muscularity: shape.muscularity,
                frame: shape.frame
            )
            let depth = PersonalBodyEstimate.depthScale(shape.depth) * scale
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
        let duration = WireframeAvatarMotion.animationDuration(reduceMotion: reduceMotion)
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

struct PersonalBodyCaptureOffer: View {
    let image: UIImage?
    let accountId: String?
    let photoId: String?
    let sessionId: String
    let effectiveDate: Date
    let frame: Double

    @State private var message = PersonalBodyEstimate.benefitCopy
    @State private var showsConsent = false
    @State private var labeled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional capture")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("personal_body_benefit")
            HStack(spacing: 8) {
                labelButton("Front", .front, "personal_body_label_front")
                labelButton("Side", .side, "personal_body_label_side")
                labelButton("Back", .back, "personal_body_label_back")
            }
            Button("Not now", action: retainDiary)
                .accessibilityIdentifier("personal_body_label_skip")
            Button("External processing") { showsConsent = true }
                .accessibilityIdentifier("personal_body_processing")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsConsent) {
            PersonalBodyConsentSheet(request: requestExternal)
        }
        .onDisappear {
            if !labeled { retainDiary() }
        }
    }

    private func labelButton(_ title: String, _ view: PersonalBodyViewKind, _ id: String) -> some View {
        Button(title) { label(view) }
            .accessibilityIdentifier(id)
    }

    private func label(_ view: PersonalBodyViewKind) {
        guard let image, let accountId, let photoId else { return }
        labeled = true
        message = "Checking this photo."
        let session = sessionId
        let account = accountId
        let photo = photoId
        let date = PersonalBodyDay.key(effectiveDate)
        let identityFrame = frame
        Task {
            let pose = await PersonalBodyPoseReader.read(image: image, view: view)
            var capture = pose
            capture.id = "\(view.rawValue)-\(photo)"
            capture.accountId = account
            capture.photoId = photo
            capture.sessionId = session
            capture.effectiveDate = date
            let receipt = await PersonalBodyEstimateStore.shared.record(
                capture,
                identity: PersonalBodyIdentity(accountId: account, bodyId: "\(account).body", frame: identityFrame),
                now: PersonalBodyClock.now,
                deadline: PersonalBodyClock.deadline
            )
            await MainActor.run {
                message = receipt.journey == "estimate" ? "Outline saved for this date." : "This photo stays in the timeline."
            }
        }
    }

    private func retainDiary() {
        guard !labeled, let accountId, let photoId else { return }
        labeled = true
        let capture = PersonalBodyCapture(
            id: "diary-\(photoId)",
            accountId: accountId,
            photoId: photoId,
            sessionId: nil,
            view: .diary,
            effectiveDate: PersonalBodyDay.key(effectiveDate),
            quality: .supported,
            torsoWidth: nil,
            torsoDepth: nil,
            dexaBodyFat: nil,
            dexaDate: nil
        )
        Task {
            _ = await PersonalBodyEstimateStore.shared.record(
                capture,
                identity: PersonalBodyIdentity(accountId: accountId, bodyId: "\(accountId).body", frame: frame),
                now: PersonalBodyClock.now,
                deadline: PersonalBodyClock.deadline
            )
        }
    }

    private func requestExternal(consent: Bool) {
        guard let accountId, let photoId else { return }
        labeled = true
        let capture = PersonalBodyCapture(
            id: "external-\(photoId)",
            accountId: accountId,
            photoId: photoId,
            sessionId: sessionId,
            view: .front,
            effectiveDate: PersonalBodyDay.key(effectiveDate),
            quality: .supported,
            torsoWidth: nil,
            torsoDepth: nil,
            dexaBodyFat: nil,
            dexaDate: nil
        )
        Task {
            let receipt = await PersonalBodyEstimateStore.shared.record(
                capture,
                identity: PersonalBodyIdentity(accountId: accountId, bodyId: "\(accountId).body", frame: frame),
                now: PersonalBodyClock.now,
                deadline: PersonalBodyClock.deadline,
                route: .external,
                consentGranted: consent,
                providerAvailable: false,
                online: true
            )
            await MainActor.run {
                message = receipt.job.failure == "denied"
                    ? "External processing was not allowed. Your photo stays in the timeline."
                    : "External processing isn't available. Your photo stays in the timeline."
            }
        }
    }
}

private enum PersonalBodyClock {
    static var now: Int { Int(Date().timeIntervalSince1970 * 1_000) }
    static var deadline: Int { now + 2_000 }
}

struct PersonalBodyConsentSheet: View {
    let request: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var acceptedPrivacy = false
    @State private var showsPrivacy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This outline is drawn on this phone. LogYourBody does not send these photos to a reconstruction service.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Read Privacy Policy") { showsPrivacy = true }
                    .accessibilityIdentifier("personal_body_privacy_policy")
                Toggle("I have read the privacy policy", isOn: $acceptedPrivacy)
                    .accessibilityIdentifier("personal_body_privacy_toggle")
                Button("Keep on this phone") {
                    request(false)
                    dismiss()
                }
                .accessibilityIdentifier("personal_body_keep_local")
                Button("Request external processing") {
                    request(true)
                    dismiss()
                }
                .disabled(!acceptedPrivacy)
                .accessibilityIdentifier("personal_body_request_external")
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Photo processing")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showsPrivacy) {
            NavigationStack { LegalDocumentView(documentType: .privacy) }
        }
        .accessibilityIdentifier("personal_body_consent")
    }
}
