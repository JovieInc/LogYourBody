//
// PhotoAnchoredTimelineSlider.swift
// LogYourBody
//
import SwiftUI
import Foundation
struct TimelineTick {
    let index: Int
    let date: Date
    let position: CGFloat
    let isMinor: Bool
    let hasPhoto: Bool
    let photoUrl: String?
    let isPhotoAnchor: Bool // True if this is a primary photo checkpoint
}

// MARK: - Photo-Anchored Timeline Slider

struct PhotoAnchoredTimelineSlider: View {
    let metrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let accentColor: Color
    
    @State private var isDragging = false
    @State private var thumbScale: CGFloat = 1.0
    
    private var progress: Double {
        guard metrics.count > 1 else { return 0 }
        return Double(selectedIndex) / Double(metrics.count - 1)
    }
    
    private func calculateSmartTicks() -> [TimelineTick] {
        guard !metrics.isEmpty else { return [] }
        
        var ticks: [TimelineTick] = []
        let calendar = Calendar.current
        
        // Find metrics with photos for anchoring
        let photoIndices = metrics.enumerated().compactMap { index, metric in
            metric.photoUrl != nil ? index : nil
        }
        
        // Create ticks for photo metrics (always visible)
        for photoIndex in photoIndices {
            let position = metrics.count > 1 ? CGFloat(photoIndex) / CGFloat(metrics.count - 1) : 0.5
            ticks.append(TimelineTick(
                index: photoIndex,
                date: metrics[photoIndex].date,
                position: position,
                isMinor: false,
                hasPhoto: true,
                photoUrl: metrics[photoIndex].photoUrl,
                isPhotoAnchor: true
            ))
        }
        
        // Add monthly ticks between photos (only if not too dense)
        if photoIndices.count < 10 {
            var currentMonth = calendar.dateComponents([.year, .month], from: metrics.first!.date)
            
            for (index, metric) in metrics.enumerated() {
                let metricMonth = calendar.dateComponents([.year, .month], from: metric.date)
                
                if metricMonth.year != currentMonth.year || metricMonth.month != currentMonth.month {
                    // New month - add tick if not already a photo tick
                    if !photoIndices.contains(index) {
                        let position = metrics.count > 1 ? CGFloat(index) / CGFloat(metrics.count - 1) : 0.5
                        ticks.append(TimelineTick(
                            index: index,
                            date: metric.date,
                            position: position,
                            isMinor: true,
                            hasPhoto: false,
                            photoUrl: nil,
                            isPhotoAnchor: false
                        ))
                    }
                    currentMonth = metricMonth
                }
            }
        }
        
        return ticks.sorted { $0.position < $1.position }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Photo navigation buttons
            if hasPhotos {
                HStack(spacing: 16) {
                    // Previous photo button
                    Button(action: navigateToPreviousPhoto) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(hasPreviousPhoto ? .white : .white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(hasPreviousPhoto ? 0.1 : 0.05))
                            )
                    }
                    .disabled(!hasPreviousPhoto)
                    
                    Spacer()
                    
                    // Current date display
                    if let date = metrics[safe: selectedIndex]?.date {
                        VStack(spacing: 2) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text(date, format: .dateTime.year())
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Next photo button
                    Button(action: navigateToNextPhoto) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(hasNextPhoto ? .white : .white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(hasNextPhoto ? 0.1 : 0.05))
                            )
                    }
                    .disabled(!hasNextPhoto)
                }
                .padding(.horizontal, 4)
            }
            
            // Timeline slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Active track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)), height: 4)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: progress)
                }
                .frame(height: 20, alignment: .center)
                
                // Photo thumbnails only (no tick lines)
                ForEach(calculateSmartTicks().filter { $0.hasPhoto }, id: \.index) { tick in
                    PhotoThumbnailTick(photoUrl: tick.photoUrl, isSelected: tick.index == selectedIndex)
                        .position(x: tick.position * geometry.size.width, y: 10)
                }
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .scaleEffect(thumbScale)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(x: geometry.size.width * CGFloat(progress), y: 10)
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: progress)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: thumbScale)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        thumbScale = 1.2
                        
                        let newProgress = value.location.x / value.translation.width
                        let clampedProgress = min(max(0, newProgress), 1)
                        let newIndex = Int(round(clampedProgress * Double(metrics.count - 1)))
                        
                        if newIndex != selectedIndex && newIndex >= 0 && newIndex < metrics.count {
                            selectedIndex = newIndex
                            HapticManager.shared.buttonTapped()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        thumbScale = 1.0
                        HapticManager.shared.buttonTapped()
                    }
            )
        }
    }
    
    // MARK: - Helper Properties
    
    private var hasPhotos: Bool {
        metrics.contains { $0.photoUrl != nil }
    }
    
    private var hasPreviousPhoto: Bool {
        guard selectedIndex > 0 else { return false }
        return metrics[0..<selectedIndex].contains { $0.photoUrl != nil }
    }
    
    private var hasNextPhoto: Bool {
        guard selectedIndex < metrics.count - 1 else { return false }
        return metrics[(selectedIndex + 1)...].contains { $0.photoUrl != nil }
    }
    
    // MARK: - Navigation Methods
    
    private func navigateToPreviousPhoto() {
        guard selectedIndex > 0 else { return }
        
        for i in stride(from: selectedIndex - 1, through: 0, by: -1) {
            if metrics[i].photoUrl != nil {
                selectedIndex = i
                HapticManager.shared.buttonTapped()
                break
            }
        }
    }
    
    private func navigateToNextPhoto() {
        guard selectedIndex < metrics.count - 1 else { return }
        
        for i in (selectedIndex + 1)..<metrics.count {
            if metrics[i].photoUrl != nil {
                selectedIndex = i
                HapticManager.shared.buttonTapped()
                break
            }
        }
    }
}

// MARK: - Photo Thumbnail Tick

struct PhotoThumbnailTick: View {
    let photoUrl: String?
    let isSelected: Bool
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            // Thumbnail container
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 16, height: 16)
            
            // Photo thumbnail
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
            } else {
                // Loading indicator
                Circle()
                    .fill(Color.appPrimary.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
            
            // Selection indicator
            if isSelected {
                Circle()
                    .stroke(Color.appPrimary, lineWidth: 2)
                    .frame(width: 18, height: 18)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task.detached(priority: .userInitiated) {
            guard let url = photoUrl, let thumbnail = await ImageLoader.shared.loadImage(from: url) else { return }
            
            let thumbnailSize = CGSize(width: 28, height: 28)
            let thumbnailImage = thumbnail.resized(to: thumbnailSize)
            
            await MainActor.run {
                self.image = thumbnailImage
            }
        }
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// Helper extension for image resizing
extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
