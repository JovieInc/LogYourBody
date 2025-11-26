import SwiftUI
import UIKit
import Photos

struct BodyScoreSharePayload {
    let score: Int
    let scoreText: String
    let tagline: String
    let ffmiValue: String
    let ffmiCaption: String
    let bodyFatValue: String
    let bodyFatCaption: String
    let weightValue: String
    let weightCaption: String
    let deltaText: String?
}

enum BodyScoreShareAspect: String, CaseIterable, Identifiable {
    case square
    case portrait
    case story

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .square:
            return "1:1"
        case .portrait:
            return "4:5"
        case .story:
            return "9:16"
        }
    }

    var pixelSize: CGSize {
        switch self {
        case .square:
            return CGSize(width: 1_080, height: 1_080)
        case .portrait:
            return CGSize(width: 1_080, height: 1_350)
        case .story:
            return CGSize(width: 1_080, height: 1_920)
        }
    }
}

struct BodyScoreShareCardView: View {
    let payload: BodyScoreSharePayload
    let aspect: BodyScoreShareAspect

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 28) {
                HStack(spacing: 12) {
                    DSLogo(size: 44, textSize: 20)

                    Text("Body Score")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()
                }

                VStack(spacing: 20) {
                    BodyScoreGaugeView(score: payload.score)
                        .frame(maxWidth: .infinity)

                    Text(payload.scoreText)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                Text("Shared from LogYourBody")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .aspectRatio(aspectRatioValue, contentMode: .fit)
    }

    private var aspectRatioValue: CGFloat {
        let size = aspect.pixelSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }
}

struct BodyScoreShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let payload: BodyScoreSharePayload

    @State private var selectedAspect: BodyScoreShareAspect = .square
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var showSystemShareSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Picker("Format", selection: $selectedAspect) {
                    ForEach(BodyScoreShareAspect.allCases) { aspect in
                        Text(aspect.displayName).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                GeometryReader { geometry in
                    let size = fittedSize(for: geometry.size, target: selectedAspect.pixelSize)

                    BodyScoreShareCardView(payload: payload, aspect: selectedAspect)
                        .frame(width: size.width, height: size.height)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    GlassPillButton(icon: "square.and.arrow.down", title: "Save") {
                        Task { await saveToPhotos() }
                    }

                    GlassPillButton(icon: "square.and.arrow.up", title: "Share") {
                        Task { await shareImage() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .disabled(isRendering)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .overlay {
                if isRendering {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()

                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
            .navigationTitle("Share Body Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSystemShareSheet) {
                if let image = renderedImage {
                    ShareSheet(items: [image])
                        .ignoresSafeArea()
                }
            }
            .onChange(of: selectedAspect) { _, _ in
                renderedImage = nil
            }
        }
    }

    private func fittedSize(for container: CGSize, target: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else {
            return target
        }

        let scale = min(container.width / target.width, container.height / target.height)
        return CGSize(width: target.width * scale, height: target.height * scale)
    }

    @MainActor
    private func renderImage() {
        isRendering = true
        defer { isRendering = false }

        let size = selectedAspect.pixelSize
        let renderer = ImageRenderer(
            content:
                BodyScoreShareCardView(payload: payload, aspect: selectedAspect)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        // Use 3x scale for high quality images (suitable for sharing)
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
    }

    @MainActor
    private func shareImage() async {
        if renderedImage == nil {
            renderImage()
        }
        guard renderedImage != nil else { return }
        showSystemShareSheet = true
    }

    @MainActor
    private func saveToPhotos() async {
        if renderedImage == nil {
            renderImage()
        }
        guard let image = renderedImage else { return }

        let status = PHPhotoLibrary.authorizationStatus()

        switch status {
        case .authorized:
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { authStatus in
                    continuation.resume(returning: authStatus)
                }
            }

            if newStatus == .authorized {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            } else if #available(iOS 14, *), newStatus == .limited {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        case .limited:
            if #available(iOS 14, *) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        default:
            return
        }
    }
}
