//
// AspectFillCropper.swift
// LogYourBody
//
// Split out of HomeV2Surface.swift to honor the per-file size budget;
// behavior is unchanged.
//
import UIKit

/// Aspect-fill crop in points. Drawing through UIKit also normalises EXIF
/// orientation, so the crop rect is computed in display space.
enum AspectFillCropper {
    static func fillRect(imageSize: CGSize, in target: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else {
            return CGRect(origin: .zero, size: target)
        }
        let scale = max(target.width / imageSize.width, target.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (target.width - drawn.width) / 2,
            y: (target.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    /// Aspect-fill where `anchor` — a normalized point in image space (x
    /// right, y down, 0–1) — lands on `anchorTarget`, a fraction of the
    /// target. Offsets clamp so the drawn image still covers the frame;
    /// a nil anchor is the centered fill above.
    static func fillRect(imageSize: CGSize, in target: CGSize, anchor: CGPoint?, anchorTarget: CGPoint) -> CGRect {
        let rect = fillRect(imageSize: imageSize, in: target)
        guard let anchor else { return rect }

        let offsetX = min(0, max(target.width - rect.width, anchorTarget.x * target.width - anchor.x * rect.width))
        let offsetY = min(0, max(target.height - rect.height, anchorTarget.y * target.height - anchor.y * rect.height))
        return CGRect(x: offsetX, y: offsetY, width: rect.width, height: rect.height)
    }

    static func crop(_ image: UIImage, to target: CGSize) -> UIImage {
        crop(image, to: target, anchor: nil)
    }

    static func crop(_ image: UIImage, to target: CGSize, anchor: CGPoint?) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        guard let registration = registration(imageSize: image.size, in: target, anchor: anchor) else {
            return UIGraphicsImageRenderer(size: target).image { _ in }
        }
        return crop(image, to: target, registration: registration)
    }

    static func registration(imageSize: CGSize, in target: CGSize, anchor: CGPoint?) -> BodyPhotoRegistration? {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else { return nil }
        let rect = fillRect(
            imageSize: imageSize,
            in: target,
            anchor: anchor,
            anchorTarget: TorsoFocusService.stageAnchor
        )
        return BodyPhotoRegistration(
            translation: rect.origin,
            scale: max(target.width / imageSize.width, target.height / imageSize.height)
        )
    }

    /// Render a disposable stage image; never rewrite the source with its crop.
    static func crop(_ image: UIImage, to target: CGSize, registration: BodyPhotoRegistration) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        return UIGraphicsImageRenderer(size: target).image { context in
            context.cgContext.concatenate(registration.transform)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
