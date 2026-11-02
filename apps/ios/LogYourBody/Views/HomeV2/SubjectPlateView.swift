//
// SubjectPlateView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct BodyPhotoRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(HomeV2PhotoCopy.retryFraming)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .padding(.horizontal, HomeV2Tokens.Space.row)
                .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                .background(HomeV2Tokens.Colors.canvas.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_v2_photo_matte_retry")
    }
}

/// Loads the photo, shows it dimmed immediately, then swaps in the plate once
/// it is rendered. The image is cropped to the stage before display so nothing
/// overflows the frame: the layout, the clip and the accessibility frame agree.
struct SubjectPlateView: View {
    let urlString: String
    let size: CGSize
    var preparedOnly = false
    var drawingRegistration: BodyPhotoRegistration?

    @State private var plate: UIImage?
    @State private var original: UIImage?
    @State private var focus: CGPoint?
    @State private var stageSized = false
    @State private var showsRetry = false

    var body: some View {
        ZStack {
            HomeV2Tokens.Colors.shell

            if let plate {
                stagePhoto(plate)
            } else if let original {
                stagePhoto(original)
                    .overlay(Color.black.opacity(0.35))
            }

            if showsRetry {
                BodyPhotoRetryButton { Task { await reload() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(HomeV2Tokens.Space.tight)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: urlString) { await load() }
    }

    private func stagePhoto(_ image: UIImage) -> some View {
        let rendered: UIImage
        if let drawingRegistration {
            rendered = AspectFillCropper.crop(image, to: size, registration: drawingRegistration)
        } else if stageSized {
            rendered = image
        } else {
            rendered = AspectFillCropper.crop(image, to: size, anchor: focus)
        }
        return Image(uiImage: rendered)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
    }

    private func load() async {
        if preparedOnly {
            plate = SubjectPlateStore.shared.scrubImage(for: urlString, target: size)
            focus = SubjectPlateStore.shared.cachedFocus(for: urlString)
            stageSized = plate != nil
            showsRetry = false
            return
        }
        if preparesStageDerivative,
           let prepared = SubjectPlateStore.shared.scrubImage(for: urlString, target: size) {
            plate = prepared
            stageSized = true
            showsRetry = retryVisible
            return
        }
        plate = nil
        stageSized = false

        guard let image = await ImageCacheService.shared.loadImage(from: urlString), !Task.isCancelled else {
            return
        }
        original = image

        if focus == nil {
            focus = await SubjectPlateStore.shared.focus(for: urlString, image: image)
            guard !Task.isCancelled else { return }
        }

        if preparesStageDerivative {
            plate = await SubjectPlateStore.shared.prepare(urlString: urlString, image: image, target: size)
            stageSized = plate != nil
        } else {
            plate = await SubjectPlateStore.shared.plate(for: urlString, image: image)
            stageSized = false
        }
        showsRetry = preparesStageDerivative && retryVisible
    }

    /// Small previews stay on the shared plate so they do not evict the stage cache.
    private var preparesStageDerivative: Bool {
        BodyPhotoStagePreparation.preparesDerivative(
            size: size,
            hasDrawingRegistration: drawingRegistration != nil
        )
    }

    private func reload() async {
        SubjectPlateStore.shared.invalidatePrepared(urlString: urlString, target: size)
        plate = nil
        stageSized = false
        await load()
    }

    private var retryVisible: Bool {
        guard size.width >= 120, size.height >= 120,
              let retry = SubjectPlateStore.shared.maskRetry(for: urlString) else { return false }
        return retry.canRetry
    }
}
