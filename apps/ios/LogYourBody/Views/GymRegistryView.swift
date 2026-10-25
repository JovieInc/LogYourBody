import SwiftUI

struct GymRegistryView: View {
    @StateObject private var registry: GymRegistryService
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.theme) private var theme
    @State private var editingGym: Gym?
    @State private var errorMessage: String?
    @State private var exerciseNames: [String]?

    init(ownership: AuthManager.ProfileSessionOwnership, authManager: AuthManager) {
        _registry = StateObject(wrappedValue: GymRegistryService(
            ownerId: ownership.subject, store: CoreDataGymRegistryStore(),
            isCurrent: { authManager.ownsAccountSession(ownership) }
        ))
    }

    var body: some View {
        Form {
            Section {
                selection("No gym selected", id: nil)
                Text("All equipment is allowed when no gym is selected. Choose a gym to use only its confirmed equipment.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            } header: { Text("Active gym") }

            Section {
                ForEach(registry.snapshot.gyms) { gym in
                    VStack(alignment: .leading, spacing: 8) {
                        selection(gym.name, id: gym.id)
                        if let region = gym.region {
                            Text(region).font(.footnote).foregroundStyle(theme.colors.textSecondary)
                        }
                        Button("Edit equipment and details") { editingGym = gym }
                            .font(.footnote)
                            .frame(minHeight: 44)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { change { try registry.remove(gym.id) } }
                    }
                }
                Button("Add gym", systemImage: "plus") {
                    editingGym = Gym(name: "", equipment: [], preferredMachines: [])
                }
                .accessibilityIdentifier("gym_registry_add")
            } header: { Text("Your gyms") }

            Section("Exercise library") {
                Button("Show matching exercises") { Task { await loadExercises() } }
                if let exerciseNames {
                    if exerciseNames.isEmpty { Text("No exercises match this equipment list.") }
                    ForEach(exerciseNames, id: \.self) { name in Text(name) }
                }
            }

            if let message = errorMessage ?? registry.errorMessage {
                Section {
                    Text(message).foregroundStyle(Color.appWarning)
                    Button("Retry sync") { Task { await synchronize() } }
                }
            }
            if registry.isSyncing { ProgressView("Syncing gyms…") }
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background)
        .navigationTitle("Gyms")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await synchronize() }
        .refreshable { await synchronize() }
        .onChange(of: registry.snapshot) { _, _ in exerciseNames = nil }
        .sheet(item: $editingGym) { gym in
            GymEditorView(gym: gym) { value in
                try registry.save(value)
                Task { await synchronize() }
            }
        }
    }

    private func selection(_ name: String, id: UUID?) -> some View {
        Button {
            change { try registry.select(id) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if registry.snapshot.activeGymId == id {
                    Image(systemName: "checkmark").accessibilityLabel("Selected")
                }
            }
            .foregroundStyle(theme.colors.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id.map { "gym_select_\($0)" } ?? "gym_select_none")
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
            Task { await synchronize() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func synchronize() async {
        await registry.synchronize(api: FirstPartyGymRegistryAdapter(client: .shared)) {
            await authManager.getAccessToken()
        }
    }

    private func loadExercises() async {
        let captured = registry.snapshot
        do {
            var names: [String] = []
            try await registry.withCurrentToken(getToken: { await authManager.getAccessToken() }, send: { token in
                names = try await FirstPartyGymRegistryAdapter(client: .shared).exerciseNames(
                    equipment: captured.equipmentFilter, token: token
                )
            })
            guard registry.snapshot == captured else { return }
            exerciseNames = names
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct GymEditorView: View {
    @State var gym: Gym
    let onSave: (Gym) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var machines = ""
    @State private var equipmentConfirmed = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gym details") {
                    TextField("Name", text: $gym.name).textContentType(.organizationName)
                    TextField("Region (optional)", text: Binding(
                        get: { gym.region ?? "" }, set: { gym.region = $0 }
                    ))
                    Text("Enter a broad area if useful, such as a city. Your location is never requested.")
                        .font(.footnote).foregroundStyle(theme.colors.textSecondary)
                }
                Section("Available equipment") {
                    ForEach(GymEquipment.allCases, id: \.self) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { gym.equipment.contains(item) },
                            set: { enabled in
                                if enabled { gym.equipment.insert(item) } else { gym.equipment.remove(item) }
                            }
                        ))
                    }
                    Toggle("I confirm this equipment list, including any empty selection.", isOn: $equipmentConfirmed)
                }
                Section("Preferred machines (optional)") {
                    TextField("One machine per line", text: $machines, axis: .vertical)
                        .lineLimit(3...6)
                    Text("Preferences do not add equipment to your inventory.")
                        .font(.footnote).foregroundStyle(theme.colors.textSecondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(Color.appWarning) }
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .navigationTitle("Gym details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(gym.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !equipmentConfirmed)
                }
            }
            .onAppear { machines = gym.preferredMachines.joined(separator: "\n") }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        do {
            gym.preferredMachines = machines.split(separator: "\n").map(String.init)
            try onSave(gym.validated())
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
