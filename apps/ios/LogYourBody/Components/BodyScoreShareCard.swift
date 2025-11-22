import SwiftUI
import UIKit

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
            return CGSize(width: 1080, height: 1080)
        case .portrait:
            return CGSize(width: 1080, height: 1350)
        case .story:
            return CGSize(width: 1080, height: 1920)
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

            VStack(spacing: 24) {
                DSLogo(size: 44, textSize: 20)

                DashboardBodyScoreHeroCard(
                    score: payload.score,
                    scoreText: payload.scoreText,
                    tagline: payload.tagline,
                    ffmiValue: payload.ffmiValue,
                    ffmiCaption: payload.ffmiCaption,
                    bodyFatValue: payload.bodyFatValue,
                    bodyFatCaption: payload.bodyFatCaption,
                    weightValue: payload.weightValue,
                    weightCaption: payload.weightCaption,
                    deltaText: payload.deltaText,
                    onTapFFMI: nil,
                    onTapBodyFat: nil,
                    onTapWeight: nil
                )

                Spacer(minLength: 0)

                Text("Shared from LogYourBody")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
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
            }
            .background(Color.appBackground.ignoresSafeArea())
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
        renderer.scale = UIScreen.main.scale
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
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
