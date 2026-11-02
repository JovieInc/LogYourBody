//
// PersonMaskPolicy.swift
// LogYourBody
//
// Mask admission, frame stroke and in-memory photo derivatives.
// The source photograph is never rewritten.
//
import CoreGraphics
import CoreVideo
import UIKit

enum PersonMaskRejection: String, Equatable {
    case lowConfidence
    case missingLimb
    case unsupportedCrop
    case interiorHole
}

struct PersonMaskRetry: Equatable {
    var reason: PersonMaskRejection
    var canRetry: Bool
}

enum PersonMaskDecision: Equatable {
    case refined(PersonMaskGrid)
    case intact(PersonMaskRetry)
}

struct PersonMaskGrid: Equatable {
    var width: Int
    var height: Int
    var values: [UInt8]

    init(width: Int, height: Int, values: [UInt8]) {
        self.width = width
        self.height = height
        self.values = values
    }

    init?(pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let start = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                values[row * width + column] = start[column]
            }
        }
        self.init(width: width, height: height, values: values)
    }

    func sample(imageX: Int, imageY: Int, imageWidth: Int, imageHeight: Int) -> UInt8 {
        guard width > 0, height > 0, imageWidth > 0, imageHeight > 0,
              imageX >= 0, imageY >= 0, imageX < imageWidth, imageY < imageHeight else { return 0 }
        let maskX = min(width - 1, imageX * width / imageWidth)
        let maskY = min(height - 1, imageY * height / imageHeight)
        return values[maskY * width + maskX]
    }
}

enum PersonMaskPolicy {
    static let foreground: UInt8 = 128
    static let hairFloor: UInt8 = 64
    static let minimumForegroundFraction: Float = 0.08
    static let minimumForegroundMean: Float = 180
    /// An interior hole larger than this fraction of the mask is a failed matte.
    static let maximumHoleFraction: Float = 0.08
    static let protectedCoverage: Float = 0.5

    static func decide(
        mask: PersonMaskGrid,
        imageWidth: Int,
        imageHeight: Int,
        protectedPoints: [CGPoint],
        cropSupported: Bool
    ) -> PersonMaskDecision {
        guard cropSupported, mask.width > 0, mask.height > 0, mask.values.count == mask.width * mask.height else {
            return .intact(PersonMaskRetry(reason: .unsupportedCrop, canRetry: true))
        }
        var refined = mask
        if let rejection = fillInteriorHoles(&refined) {
            return .intact(PersonMaskRetry(reason: rejection, canRetry: true))
        }
        includeSoftEdges(&refined)
        let count = foregroundCount(refined)
        let fraction = Float(count) / Float(refined.values.count)
        if count == 0 || fraction < minimumForegroundFraction || foregroundMean(refined) < minimumForegroundMean {
            return .intact(PersonMaskRetry(reason: .lowConfidence, canRetry: true))
        }
        if clipsProtectedPoint(refined, imageWidth: imageWidth, imageHeight: imageHeight, points: protectedPoints) {
            return .intact(PersonMaskRetry(reason: .missingLimb, canRetry: true))
        }
        return .refined(refined)
    }

    private static func fillInteriorHoles(_ mask: inout PersonMaskGrid) -> PersonMaskRejection? {
        let count = mask.values.count
        var reachable = [Bool](repeating: false, count: count)
        var queue = [Int]()
        queue.reserveCapacity(count / 4)
        func enqueue(_ index: Int) {
            guard mask.values[index] < foreground, !reachable[index] else { return }
            reachable[index] = true
            queue.append(index)
        }
        for column in 0..<mask.width {
            enqueue(column)
            enqueue((mask.height - 1) * mask.width + column)
        }
        if mask.height > 2 {
            for row in 1..<(mask.height - 1) {
                enqueue(row * mask.width)
                enqueue(row * mask.width + mask.width - 1)
            }
        }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let row = index / mask.width
            let column = index % mask.width
            if column > 0 { enqueue(index - 1) }
            if column + 1 < mask.width { enqueue(index + 1) }
            if row > 0 { enqueue(index - mask.width) }
            if row + 1 < mask.height { enqueue(index + mask.width) }
        }
        var holes = [Int]()
        for index in mask.values.indices where mask.values[index] < foreground && !reachable[index] {
            holes.append(index)
        }
        let limit = Int(maximumHoleFraction * Float(count))
        if holes.count > limit { return .interiorHole }
        for index in holes {
            mask.values[index] = 255
        }
        return nil
    }

    private static func includeSoftEdges(_ mask: inout PersonMaskGrid) {
        let original = mask.values
        for row in 0..<mask.height {
            for column in 0..<mask.width {
                let index = row * mask.width + column
                guard original[index] >= hairFloor, original[index] < foreground else { continue }
                let touchesPerson =
                    (column > 0 && original[index - 1] >= foreground) ||
                    (column + 1 < mask.width && original[index + 1] >= foreground) ||
                    (row > 0 && original[index - mask.width] >= foreground) ||
                    (row + 1 < mask.height && original[index + mask.width] >= foreground)
                if touchesPerson { mask.values[index] = 200 }
            }
        }
    }

    private static func foregroundCount(_ mask: PersonMaskGrid) -> Int {
        mask.values.reduce(0) { $1 >= foreground ? $0 + 1 : $0 }
    }

    private static func foregroundMean(_ mask: PersonMaskGrid) -> Float {
        var total = 0
        var count = 0
        for value in mask.values where value >= foreground {
            total += Int(value)
            count += 1
        }
        guard count > 0 else { return 0 }
        return Float(total) / Float(count)
    }

    private static func clipsProtectedPoint(
        _ mask: PersonMaskGrid,
        imageWidth: Int,
        imageHeight: Int,
        points: [CGPoint]
    ) -> Bool {
        guard imageWidth > 0, imageHeight > 0 else { return false }
        let radius = max(1, min(mask.width, mask.height) / 25)
        for point in points {
            let centerX = Int(point.x / CGFloat(imageWidth) * CGFloat(mask.width))
            let centerY = Int(point.y / CGFloat(imageHeight) * CGFloat(mask.height))
            guard centerX >= 0, centerY >= 0, centerX < mask.width, centerY < mask.height else { continue }
            var covered = 0
            var samples = 0
            for row in (centerY - radius)...(centerY + radius) {
                guard row >= 0, row < mask.height else { continue }
                for column in (centerX - radius)...(centerX + radius) {
                    guard column >= 0, column < mask.width else { continue }
                    samples += 1
                    if mask.values[row * mask.width + column] >= foreground { covered += 1 }
                }
            }
            if samples > 0, Float(covered) / Float(samples) < protectedCoverage { return true }
        }
        return false
    }
}

/// Approved Home frame tokens, checked against `HomeV2Tokens` by the unit tests.
enum BodyPhotoFrameTreatment {
    static let overlap: CGFloat = 8
    static let inset: CGFloat = 12
    static let radius: CGFloat = 12
    static let stroke: CGFloat = 2
    static let strokeAlpha: Float = 0.35

    static func frameRect(in stage: CGSize) -> CGRect {
        guard stage.width > 1, stage.height > 1 else { return .zero }
        let inset = min(self.inset, max(1, min(stage.width, stage.height) / 6))
        let rect = CGRect(
            x: inset,
            y: inset,
            width: stage.width - inset * 2,
            height: stage.height - inset * 2
        )
        guard rect.width > 1, rect.height > 1 else { return CGRect(origin: .zero, size: stage) }
        return rect
    }

    static func insetPixels(width: Int, height: Int) -> Int {
        let shortest = min(width, height)
        guard shortest > 2 else { return 0 }
        return min(Int(inset.rounded()), max(1, shortest / 6))
    }

    static func isStroke(x: Int, y: Int, width: Int, height: Int) -> Bool {
        let inset = insetPixels(width: width, height: height)
        let stroke = max(1, Int(self.stroke.rounded()))
        guard inset > 0, width > inset * 2 + stroke, height > inset * 2 + stroke else { return false }
        let outerMinX = inset
        let outerMinY = inset
        let outerMaxX = width - inset
        let outerMaxY = height - inset
        let insideOuter = x >= outerMinX && y >= outerMinY && x < outerMaxX && y < outerMaxY
        let innerMinX = outerMinX + stroke
        let innerMinY = outerMinY + stroke
        let innerMaxX = outerMaxX - stroke
        let innerMaxY = outerMaxY - stroke
        let insideInner = x >= innerMinX && y >= innerMinY && x < innerMaxX && y < innerMaxY
        return insideOuter && !insideInner
    }
}

enum BodyPhotoCompositor {
    static func composite(
        source: [UInt8],
        background: [UInt8],
        width: Int,
        height: Int,
        mask: PersonMaskGrid
    ) -> [UInt8]? {
        let count = width * height * 4
        guard width > 0, height > 0, source.count == count, background.count == count else { return nil }
        var output = background
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let sample = mask.sample(imageX: column, imageY: row, imageWidth: width, imageHeight: height)
                if sample >= PersonMaskPolicy.foreground {
                    output[offset] = source[offset]
                    output[offset + 1] = source[offset + 1]
                    output[offset + 2] = source[offset + 2]
                    output[offset + 3] = 255
                } else if BodyPhotoFrameTreatment.isStroke(x: column, y: row, width: width, height: height) {
                    blendFrame(into: &output, offset: offset)
                }
            }
        }
        return output
    }

    /// Columns whose pixels still match the source subject. Used to prove the silhouette was not rescaled.
    static func subjectWidth(
        pixels: [UInt8],
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> Int {
        guard width > 0, height > 0, pixels.count == width * height * 4 else { return 0 }
        var columns = 0
        for column in 0..<width {
            for row in 0..<height {
                let offset = (row * width + column) * 4
                if pixels[offset] == red, pixels[offset + 1] == green, pixels[offset + 2] == blue {
                    columns += 1
                    break
                }
            }
        }
        return columns
    }

    private static func blendFrame(into pixels: inout [UInt8], offset: Int) {
        let alpha = BodyPhotoFrameTreatment.strokeAlpha
        for channel in 0..<3 {
            let mixed = Float(pixels[offset + channel]) * (1 - alpha) + 255 * alpha
            pixels[offset + channel] = UInt8(min(255, max(0, mixed.rounded())))
        }
        pixels[offset + 3] = 255
    }
}

struct BodyPhotoTransition: Equatable {
    var earlierDate: Date
    var laterDate: Date
    var earlierSourceID: String
    var laterSourceID: String
    var progress: CGFloat

    var earlierOpacity: Double { Double(1 - min(max(progress, 0), 1)) }
    var laterOpacity: Double { Double(min(max(progress, 0), 1)) }
    var isPersistedCapture: Bool { false }

    static func crossDissolve(
        earlierDate: Date,
        earlierID: String,
        laterDate: Date,
        laterID: String,
        progress: CGFloat
    ) -> BodyPhotoTransition? {
        guard !earlierID.isEmpty, !laterID.isEmpty, earlierID != laterID, progress.isFinite else { return nil }
        return BodyPhotoTransition(
            earlierDate: earlierDate,
            laterDate: laterDate,
            earlierSourceID: earlierID,
            laterSourceID: laterID,
            progress: progress
        )
    }
}

enum BodyPhotoCaptureLog {
    /// A dissolve is a view over two captures. It does not append a capture.
    static func idsAfterTransition(existing: [String], transition: BodyPhotoTransition) -> [String] {
        _ = transition.isPersistedCapture
        return existing
    }
}

struct BodyPhotoDerivative: Equatable {
    var url: String
    var targetSize: CGSize
    var mask: PersonMaskGrid?
    var fellBackToIntact: Bool
    var retry: PersonMaskRetry?
    var metadata: BodyPhotoCaptureMetadata
}

struct BodyPhotoDerivativeCache {
    static let capacity = 5
    private(set) var entries: [String: BodyPhotoDerivative] = [:]
    private var order: [String] = []

    static func key(url: String, size: CGSize) -> String {
        "\(url)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    func prepared(url: String, size: CGSize) -> BodyPhotoDerivative? {
        entries[Self.key(url: url, size: size)]
    }

    /// `retaining` drops derivatives outside the adjacent-date window. Nil keeps
    /// every stored URL and only enforces the capacity bound.
    mutating func store(_ derivative: BodyPhotoDerivative, retaining urls: [String]?) {
        let key = Self.key(url: derivative.url, size: derivative.targetSize)
        entries[key] = derivative
        order.removeAll { $0 == key }
        order.append(key)
        if let urls {
            let keep = Set(urls)
            for stored in order where entries[stored].map({ keep.contains($0.url) }) != true {
                entries[stored] = nil
            }
            order.removeAll { entries[$0] == nil }
        }
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }
}

struct BodyPhotoScrubWork: Equatable {
    var segmentations: Int
    var fullResolutionDecodes: Int
}

enum BodyPhotoStagePreparation {
    /// Thumbnails keep the shared full-frame plate. A stage at least this wide
    /// stores a target-sized derivative the scrubber can read without segmenting.
    static let minimumSide: CGFloat = 120

    static func preparesDerivative(size: CGSize, hasDrawingRegistration: Bool) -> Bool {
        !hasDrawingRegistration && min(size.width, size.height) >= minimumSide
    }
}

enum BodyPhotoPreparationPlan {
    static func neighborURLs(around index: Int, urls: [String?]) -> [String] {
        guard urls.indices.contains(index) else { return [] }
        let lower = max(0, index - 1)
        let upper = min(urls.count - 1, index + 1)
        var window: [String] = []
        for candidate in urls[lower...upper] {
            guard let candidate, !candidate.isEmpty, !window.contains(candidate) else { continue }
            window.append(candidate)
        }
        return window
    }
}

enum BodyPhotoScrubSession {
    /// Scrub frames read a prepared derivative. They do not segment or decode.
    static func display(prepared: BodyPhotoDerivative?) -> BodyPhotoDerivative? {
        prepared
    }

    static var work: BodyPhotoScrubWork {
        BodyPhotoScrubWork(segmentations: 0, fullResolutionDecodes: 0)
    }
}

enum BodyPhotoBitmap {
    static func read(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    static func image(
        pixels: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat,
        orientation: UIImage.Orientation
    ) -> UIImage? {
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }
}
