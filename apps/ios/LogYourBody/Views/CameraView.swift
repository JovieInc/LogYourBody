//
// CameraView.swift
// LogYourBody
//
import SwiftUI
import UIKit
import PhotosUI

struct CameraView: View {
    let onImageCaptured: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPose = "Front"
    @State private var showsSettings = false
    @State private var showsSystemCamera = false
    @State private var showsLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var reviewImage: UIImage?
    @State private var timerSeconds = 0

    private let poses = ["Front", "Side", "Back"]

    #if DEBUG
    private var usesFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-lybUITestProgressPhotoReviewFixture")
    }
    #else
    private let usesFixture = false
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let reviewImage {
                review(image: reviewImage)
            } else {
                capture
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .fullScreenCover(isPresented: $showsSystemCamera) {
            PlatformCameraCaptureView { image in
                reviewImage = image
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run { reviewImage = image }
            }
        }
        .onAppear {
            #if DEBUG
            if usesFixture { reviewImage = makeFixturePhoto() }
            #endif
        }
        .accessibilityIdentifier("progress_photo_camera")
    }

    private var capture: some View {
        VStack(spacing: 0) {
            cameraHeader(title: "Take photo")
            ZStack {
                LinearGradient(colors: [Color(white: 0.12), Color(white: 0.025)], startPoint: .top, endPoint: .bottom)
                ghostPhoto
                PoseGuide()
                VStack {
                    Spacer()
                    Text("Same spot, same light, every time")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.55), in: Capsule())
                        .accessibilityIdentifier("progress_photo_camera_tip")
                        .padding(.bottom, 18)
                }
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            Spacer(minLength: 12)
            captureBar
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var captureBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Library") { showsLibrary = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 76)
                    .accessibilityLabel("Choose from Library")
                    .accessibilityIdentifier("progress_photo_camera_library")
                Button { showsSystemCamera = true } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 76, height: 76)
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 4).padding(5))
                }
                .accessibilityLabel("Capture photo")
                .accessibilityIdentifier("progress_photo_camera_shutter")
                Button { showsSettings.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture settings")
                        Text("\(selectedPose)  ⌄").foregroundStyle(.white.opacity(0.65))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 104, alignment: .leading)
                }
                .accessibilityLabel("Capture settings, \(selectedPose)")
                .accessibilityIdentifier("progress_photo_camera_settings")
            }
            if showsSettings {
                HStack(spacing: 8) {
                    ForEach(poses, id: \.self) { pose in
                        Button(pose) { selectedPose = pose }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedPose == pose ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedPose == pose ? .white : .white.opacity(0.12), in: Capsule())
                    }
                    Button(timerSeconds == 0 ? "Timer off" : "\(timerSeconds)s") {
                        timerSeconds = timerSeconds == 0 ? 3 : 0
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .accessibilityIdentifier("progress_photo_camera_settings_panel")
            }
        }
        .foregroundStyle(.white)
    }

    private func review(image: UIImage) -> some View {
        VStack(spacing: 0) {
            cameraHeader(title: "Review photo")
            Image(uiImage: image)
                .resizable()
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .accessibilityLabel("Photo review")
                .accessibilityIdentifier("progress_photo_review_plate")
            VStack(alignment: .leading, spacing: 6) {
                Text("\(selectedPose) · \(HomeV2Copy.todayDateText(Date()))")
                    .font(.system(size: 16, weight: .semibold))
                Text("Not saved · Pose matched to \(matchedDateText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Spacer(minLength: 12)
            Button("Retake") { reviewImage = nil }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .accessibilityIdentifier("progress_photo_review_retake")
            Button {
                onImageCaptured(image)
                dismiss()
            } label: {
                Text("Save photo")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: Capsule())
            }
            .accessibilityIdentifier("progress_photo_review_save")
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func cameraHeader(title: String) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityIdentifier("progress_photo_camera_cancel")
            Spacer()
            Text(title).font(.system(size: 17, weight: .bold))
            Spacer()
            Color.clear.frame(width: 52)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private var matchedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date().addingTimeInterval(-86400))
    }

    private var ghostPhoto: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 220))
            .foregroundStyle(.white.opacity(0.08))
            .accessibilityHidden(true)
    }

    #if DEBUG
    private func makeFixturePhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1_125)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1))
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            context.cgContext.setFillColor(CGColor(red: 0.46, green: 0.48, blue: 0.53, alpha: 1))
            context.cgContext.fillEllipse(in: CGRect(x: 325, y: 130, width: 250, height: 250))
            context.cgContext.fill(CGRect(x: 270, y: 350, width: 360, height: 610))
        }
    }
    #endif
}

private struct PoseGuide: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width * 0.46
                let height = proxy.size.height * 0.78
                let rect = CGRect(x: (proxy.size.width - width) / 2, y: (proxy.size.height - height) / 2, width: width, height: height)
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: width / 2, height: width / 2))
            }
            .stroke(.white.opacity(0.62), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }
        .accessibilityIdentifier("progress_photo_camera_pose_guide")
        .accessibilityHidden(true)
    }
}
