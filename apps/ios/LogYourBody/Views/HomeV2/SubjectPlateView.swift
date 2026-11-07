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
/// it is rendered. The stage crop runs once per photo and size. A layout pass
/// only displays that image, so the frame, the clip and the accessibility
/// frame stay in agreement without redrawing the source bitmap.
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
                framed(plate, fills: false)
            } else if let original {
                framed(original, fills: true)
                    .overlay(Color.black.opacity(0.35))
            }

            if showsRetry {
                BodyPhotoRetryButton { Task { await reload() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(HomeV2Tokens.Space.tight)
            }
        }
        .frame(width: safeSize.width, height: safeSize.height)
        .clipped()
        .task(id: loadToken) { await load() }
    }

    /// A prepared plate already matches the stage. The dimmed source only fills
    /// the frame visually until that one crop is stored.
    @ViewBuilder
    private func framed(_ image: UIImage, fills: Bool) -> some View {
        if fills {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: safeSize.width, height: safeSize.height)
                .clipped()
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: safeSize.width, height: safeSize.height)
                .clipped()
        }
    }

    private var loadToken: String {
        // Quantize so a presenting sheet's intermediate widths share one crop.
        let quantum: CGFloat = 16
        let width = size.width.isFinite ? Int((size.width / quantum).rounded()) : 0
        let height = size.height.isFinite ? Int((size.height / quantum).rounded()) : 0
        let registration = drawingRegistration.map { registration in
            [
                registration.translation.x, registration.translation.y,
                registration.rotation, registration.scale
            ].map { String(format: "%.3f", $0) }.joined(separator: ",")
        } ?? ""
        return "\(urlString)|\(width)x\(height)|\(registration)"
    }

    private var safeSize: CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return .zero
        }
        return size
    }

    /// Geometry readers can propose a non-finite or enormous size while a sheet
    /// is presenting. Refuse that crop instead of allocating a bitmap for it.
    private var canCropToStage: Bool {
        safeSize.width > 0 && safeSize.height > 0 && safeSize.width <= 2_048 && safeSize.height <= 2_048
    }

    private func load() async {
        // A GeometryReader reports several sizes while a sheet presents. Wait
        // so only the settled size segments and crops, and a cached scrub
        // frame is never delayed.
        if !preparedOnly {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
        }
        guard canCropToStage else { return }
        if preparedOnly {
            plate = SubjectPlateStore.shared.scrubImage(for: urlString, target: safeSize)
            focus = SubjectPlateStore.shared.cachedFocus(for: urlString)
            stageSized = plate != nil
            showsRetry = false
            return
        }
        if preparesStageDerivative,
           let prepared = SubjectPlateStore.shared.scrubImage(for: urlString, target: safeSize) {
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
            let anchor = await SubjectPlateStore.shared.focus(for: urlString, image: image)
            guard !Task.isCancelled else { return }
            focus = anchor
        }

        if let drawingRegistration {
            let shared = await SubjectPlateStore.shared.plate(for: urlString, image: image)
            guard !Task.isCancelled, canCropToStage else { return }
            plate = AspectFillCropper.crop(shared ?? image, to: safeSize, registration: drawingRegistration)
            stageSized = true
            showsRetry = false
            return
        }

        if preparesStageDerivative {
            let prepared = await SubjectPlateStore.shared.prepare(
                urlString: urlString, image: image, target: safeSize
            )
            guard !Task.isCancelled else { return }
            plate = prepared
            stageSized = plate != nil
        } else {
            let shared = await SubjectPlateStore.shared.plate(for: urlString, image: image)
            guard !Task.isCancelled, canCropToStage else { return }
            plate = AspectFillCropper.crop(shared ?? image, to: safeSize, anchor: focus)
            stageSized = true
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
