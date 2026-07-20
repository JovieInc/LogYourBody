//
// SyntheticImageFixtures.swift
// LogYourBodyTests
//
// Deterministic in-memory image fixtures for Vision/photo-pipeline tests.
// Every bitmap is generated in code with fixed pixels — no randomness and no
// asset-catalog dependencies.

import UIKit
import CoreVideo

enum SyntheticImage {
    typealias RGBA = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

    /// Solid-color CGImage with exact pixel dimensions (8-bit RGBA, premultiplied-last).
    static func solidCGImage(
        width: Int,
        height: Int,
        red: UInt8 = 160,
        green: UInt8 = 160,
        blue: UInt8 = 160,
        alpha: UInt8 = 255
    ) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = alpha
        }
        return makeCGImage(width: width, height: height, pixels: pixels)
    }

    /// CGImage whose top half (CG row order: row 0 is the top) is `top` and bottom half is `bottom`.
    static func horizontalSplitCGImage(width: Int, height: Int, top: RGBA, bottom: RGBA) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let color = row < height / 2 ? top : bottom
            for column in 0..<width {
                let offset = (row * width + column) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }
        return makeCGImage(width: width, height: height, pixels: pixels)
    }

    /// CGImage whose left half is `left` and right half is `right`.
    static func verticalSplitCGImage(width: Int, height: Int, left: RGBA, right: RGBA) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let color = column < width / 2 ? left : right
                let offset = (row * width + column) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }
        return makeCGImage(width: width, height: height, pixels: pixels)
    }

    /// 8-bit grayscale CVPixelBuffer filled with a constant value (Vision-style segmentation mask).
    static func constantMask(width: Int, height: Int, value: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            memset(base + row * bytesPerRow, Int32(value), width)
        }
        return buffer
    }

    /// Exact pixel readback: draws 1:1 into a known RGBA bitmap and returns the pixel at (x, y).
    static func pixel(of cgImage: CGImage, x: Int, y: Int) -> RGBA? {
        let width = cgImage.width
        let height = cgImage.height
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
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
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    /// Decodes PNG data back into a CGImage (round-trip assertions for upload payloads).
    static func decodePNG(_ data: Data) -> CGImage? {
        UIImage(data: data)?.cgImage
    }

    private static func makeCGImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
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
        )
    }
}
