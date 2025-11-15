//
// LogWeightView.swift
// LogYourBody
//
import SwiftUI

struct LogWeightView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var weight: String = ""
    @State private var bodyFat: String = ""
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @Environment(\.dismiss)
    var dismiss
    @FocusState private var focusedField: Field?
    
    enum Field {
        case weight, bodyFat
    }
    
    var currentSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(
            action: { dismiss() },
            label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.appTextSecondary)
                                .frame(width: 44, height: 44)
                        }
        )
                        
                        Spacer()
                        
                        Text("Log Metrics")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.appText)
                        
                        Spacer()
                        
                        // Quick add button (optional)
                        Button(action: quickAdd) {
                            Text("Quick")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.appPrimary)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    ScrollView {
                        VStack(spacing: 32) {
                            // Hero section with both inputs
                            VStack(spacing: 24) {
                                // Weight input card
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "scalemass.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.blue)
                                        Text("Weight")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.appText)
                                        Spacer()
                                    }
                                    
                                    HStack(alignment: .bottom, spacing: 8) {
                                        TextField("--", text: $weight)
                                            .font(.system(size: 40, weight: .bold, design: .rounded))
                                            .foregroundColor(.appText)
                                            .multilineTextAlignment(.center)
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .weight)
                                            .frame(maxWidth: 150)
                                        
                                        Text(currentSystem.weightUnit)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.appTextSecondary)
                                            .padding(.bottom, 6)
                                    }
                                }
                                .padding(20)
                                .background(Color.appCard)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(focusedField == .weight ? Color.appPrimary : Color.appBorder, lineWidth: focusedField == .weight ? 2 : 1)
                                )
                                .onTapGesture {
                                    focusedField = .weight
                                }
                                
                                // Body fat input card
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "percent")
                                            .font(.system(size: 20))
                                            .foregroundColor(.orange)
                                        Text("Body Fat")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.appText)
                                        Spacer()
                                        Text("Optional")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.appTextTertiary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.appTextTertiary.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    
                                    HStack(alignment: .bottom, spacing: 8) {
                                        TextField("--", text: $bodyFat)
                                            .font(.system(size: 40, weight: .bold, design: .rounded))
                                            .foregroundColor(.appText)
                                            .multilineTextAlignment(.center)
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .bodyFat)
                                            .frame(maxWidth: 150)
                                        
                                        Text("%")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.appTextSecondary)
                                            .padding(.bottom, 6)
                                    }
                                }
                                .padding(20)
                                .background(Color.appCard)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(focusedField == .bodyFat ? Color.appPrimary : Color.appBorder, lineWidth: focusedField == .bodyFat ? 2 : 1)
                                )
                                .onTapGesture {
                                    focusedField = .bodyFat
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            
                            // Date and helpful info
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                        .foregroundColor(.appTextSecondary)
                                    Text("Today, \(Date(), style: .date)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                }
                                
                                if !weight.isEmpty || !bodyFat.isEmpty {
                                    VStack(spacing: 8) {
                                        if !weight.isEmpty, let weightValue = Double(weight) {
                                            let convertedWeight = currentSystem.weightUnit == "lbs" ? weightValue * 0.453592 : weightValue
                                            HStack {
                                                Text("Weight:")
                                                    .foregroundColor(.appTextSecondary)
                                                Spacer()
                                                Text("\(convertedWeight, specifier: "%.1f") kg")
                                                    .foregroundColor(.appText)
                                            }
                                            .font(.system(size: 14))
                                        }
                                        
                                        if !bodyFat.isEmpty, let bfValue = Double(bodyFat) {
                                            HStack {
                                                Text("Body Fat:")
                                                    .foregroundColor(.appTextSecondary)
                                                Spacer()
                                                Text("\(bfValue, specifier: "%.1f")%")
                                                    .foregroundColor(.appText)
                                            }
                                            .font(.system(size: 14))
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.appPrimary.opacity(0.05))
                                    .cornerRadius(12)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            Spacer(minLength: 120)
                        }
                    }
                    
                    // Save button (fixed at bottom)
                    VStack(spacing: 12) {
                        if showSuccess {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Saved successfully!")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        Button(action: saveMeasurement) {
                            Group {
                                if isLoading {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                        Text("Saving...")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                } else {
                                    Text("Save Measurement")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(height: 54)
                            .frame(maxWidth: .infinity)
                            .background(isFormValid() ? Color.appPrimary : Color.appBorder)
                            .cornerRadius(16)
                            .scaleEffect(isFormValid() ? 1.0 : 0.98)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFormValid())
                        }
                        .disabled(!isFormValid() || isLoading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                    }
                    .background(
                        Color.appBackground
                            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: -10)
                    )
                }
            }
            .preferredColorScheme(.dark)
            .onTapGesture {
                hideKeyboard()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Auto-focus on weight field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .weight
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func isFormValid() -> Bool {
        return !weight.isEmpty || !bodyFat.isEmpty
    }
    
    private func quickAdd() {
        Task {
            // Get last logged values for quick entry
            guard let userId = authManager.currentUser?.id else { return }
            let fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let cachedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId, from: fromDate, to: Date())
            let recentMetrics = cachedMetrics.compactMap { $0.toBodyMetrics() }.sorted { $0.date > $1.date }

            if let latest = recentMetrics.first {
                await MainActor.run {
                    if weight.isEmpty, let latestWeight = latest.weight {
                        let displayWeight = currentSystem.weightUnit == "lbs" ? latestWeight * 2.20462 : latestWeight
                        weight = String(format: "%.1f", displayWeight)
                    }
                    if bodyFat.isEmpty, let latestBodyFat = latest.bodyFatPercentage {
                        bodyFat = String(format: "%.1f", latestBodyFat)
                    }
                }
            }
        }
    }
    
    private func saveMeasurement() {
        isLoading = true
        hideKeyboard()
        
        Task {
            do {
                var weightValue: Double?
                var bodyFatValue: Double?
                
                // Parse weight if provided
                if !weight.isEmpty {
                    guard let w = Double(weight) else {
                        await MainActor.run {
                            errorMessage = "Please enter a valid weight"
                            showError = true
                            isLoading = false
                        }
                        return
                    }
                    weightValue = w
                }
                
                // Parse body fat if provided
                if !bodyFat.isEmpty {
                    guard let bf = Double(bodyFat), bf >= 0, bf <= 100 else {
                        await MainActor.run {
                            errorMessage = "Please enter a valid body fat percentage (0-100)"
                            showError = true
                            isLoading = false
                        }
                        return
                    }
                    bodyFatValue = bf
                }
                
                // At least one value must be provided
                guard weightValue != nil || bodyFatValue != nil else {
                    await MainActor.run {
                        errorMessage = "Please enter at least one measurement"
                        showError = true
                        isLoading = false
                    }
                    return
                }
                
                // Convert weight to kg for storage
                let weightInKg = weightValue != nil ? (currentSystem.weightUnit == "lbs" ? weightValue! * 0.453592 : weightValue!) : nil
                
                // Save to HealthKit if authorized
                if healthKitManager.isAuthorized {
                    if let w = weightValue {
                        let weightInLbs = currentSystem.weightUnit == "kg" ? w * 2.20462 : w
                        try await healthKitManager.saveWeight(weightInLbs, date: Date())
                    }
                    
                    if let bf = bodyFatValue {
                        try await healthKitManager.saveBodyFatPercentage(bf / 100, date: Date())
                    }
                }
                
                // If only body fat is provided, try to get latest weight
                var finalWeight = weightInKg
                if weightInKg == nil && bodyFatValue != nil, let userId = authManager.currentUser?.id {
                    let fromDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                    let cachedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId, from: fromDate, to: Date())
                    let recentMetrics = cachedMetrics.compactMap { $0.toBodyMetrics() }.sorted { $0.date > $1.date }
                    finalWeight = recentMetrics.first?.weight
                }
                
                // Create body metrics
                let metrics = BodyMetrics(
                    id: UUID().uuidString,
                    userId: authManager.currentUser?.id ?? "",
                    date: Date(),
                    weight: finalWeight,
                    weightUnit: finalWeight != nil ? "kg" : nil,
                    bodyFatPercentage: bodyFatValue,
                    bodyFatMethod: bodyFatValue != nil ? "Manual" : nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: nil,
                    photoUrl: nil,
                    dataSource: "Manual",
                    createdAt: Date(),
                    updatedAt: Date()
                )
                
                // Save to local storage and sync
                if let userId = authManager.currentUser?.id {
                    await MainActor.run {
                        CoreDataManager.shared.saveBodyMetrics(metrics, userId: userId, markAsSynced: false)
                    }
                    RealtimeSyncManager.shared.syncIfNeeded()
                }
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
                
                // Show success briefly then dismiss
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct LogWeightView_Previews: PreviewProvider {
    static var previews: some View {
        LogWeightView()
            .environmentObject(AuthManager.shared)
            .environmentObject(RealtimeSyncManager.shared)
            .preferredColorScheme(.dark)
    }
}
