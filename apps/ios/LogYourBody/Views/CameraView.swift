//
// CameraView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct CameraView: View {
    let onImageCaptured: (UIImage) -> Void

    var body: some View {
        PlatformCameraCaptureView(onImageCaptured: onImageCaptured)
    }
}
