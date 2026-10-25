import SwiftUI

struct GymRegistryView: View {
    let ownerID: String
    let accessToken: () async -> String?
    let isCurrent: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var registry: GymRegistry?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let registry {
                    GymRegistryContent(registry: registry, accessToken: accessToken, isCurrent: isCurrent)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Gyms unavailable", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try again", action: load)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Your gyms")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private func load() {
        guard isCurrent() else { return }
        do {
            let context = CoreDataManager.shared.persistentContainer.newBackgroundContext()
            registry = try GymRegistry(
                ownerID: ownerID, persistence: CoreDataGymRegistryStore(context: context), remote: GymRegistryAPI()
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private enum GymEditorPresentation: Identifiable {
    case new
    case edit(Gym)
    var id: String {
        switch self {
        case .new: "new"
        case .edit(let gym): gym.id.uuidString
        }
    }
    var gym: Gym? {
        if case .edit(let gym) = self { return gym }
        return nil
    }
}

private struct GymRegistryContent: View {
    @ObservedObject var registry: GymRegistry
    let accessToken: () async -> String?
    let isCurrent: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: GymEditorPresentation?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                selectionRow(title: "No gym selected", id: nil)
                ForEach(registry.gyms) { gym in
                    HStack {
                        selectionRow(title: gym.name, id: gym.id)
                        Button { editor = .edit(gym) } label: {
                            Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(gym.name)")
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { change { try registry.delete(gym.id) } }
                    }
                }
                Button("Add gym", systemImage: "plus") { editor = .new }
                    .accessibilityIdentifier("gym_add")
            } header: {
                Text("Active gym")
            } footer: {
                Text("Choose a gym manually. No selection allows all equipment in the exercise library. " +
                     "Adding a gym does not select it.")
            }
            Section {
                NavigationLink("Browse available exercises") {
                    GymExerciseLibraryView(registry: registry, accessToken: accessToken, isCurrent: isCurrent)
                }
            } footer: {
                Text("Only equipment you confirm for the selected gym is used to filter exercises.")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.secondary)
                    Button("Retry sync") { Task { await sync() } }
                }
            } else if registry.hasPendingChanges {
                Text("Saved on this device. Sync pending.").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editor) { presentation in
            GymEditorView(gym: presentation.gym) { gym in
                guard isCurrent() else { throw GymRegistryError.accountChanged }
                if presentation.gym == nil {
                    try registry.create(
                        name: gym.name, coarseRegion: gym.coarseRegion,
                        equipment: gym.equipment, preferredMachines: gym.preferredMachines
                    )
                } else {
                    try registry.update(gym)
                }
                Task { await sync() }
            }
        }
        .task { await sync() }
        .refreshable { await sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await sync() } }
        }
    }

    private func selectionRow(title: String, id: UUID?) -> some View {
        Button {
            change { try registry.select(id) }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if registry.activeGym?.id == id { Image(systemName: "checkmark") }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(registry.activeGym?.id == id ? .isSelected : [])
        .accessibilityIdentifier("gym_select_\(id?.uuidString ?? "none")")
    }

    private func change(_ action: () throws -> Void) {
        guard isCurrent() else { return }
        do {
            try action()
            errorMessage = nil
            Task { await sync() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sync() async {
        guard isCurrent() else { return }
        do {
            guard let token = await accessToken(), isCurrent() else { throw GymRegistryError.accountChanged }
            try await registry.sync(accessToken: token, isCurrent: isCurrent)
            if isCurrent() { errorMessage = nil }
        } catch {
            if isCurrent() { errorMessage = "Saved changes stay on this device. " + error.localizedDescription }
        }
    }
}

private struct GymEditorView: View {
    let gym: Gym?
    let save: (Gym) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var region: String
    @State private var equipment: Set<GymEquipment>
    @State private var machines: String
    @State private var errorMessage: String?

    init(gym: Gym?, save: @escaping (Gym) throws -> Void) {
        self.gym = gym
        self.save = save
        _name = State(initialValue: gym?.name ?? "")
        _region = State(initialValue: gym?.coarseRegion ?? "")
        _equipment = State(initialValue: gym?.equipment ?? [])
        _machines = State(initialValue: gym?.preferredMachines.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gym name", text: $name).accessibilityIdentifier("gym_name")
                    TextField("Region (optional)", text: $region)
                } footer: {
                    Text("A broad region such as a city is optional. Enter it yourself.")
                }
                Section {
                    ForEach(GymEquipment.allCases) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { equipment.contains(item) },
                            set: { enabled in
                                if enabled { equipment.insert(item) } else { equipment.remove(item) }
                            }
                        ))
                    }
                } header: {
                    Text("Available equipment")
                } footer: {
                    Text("Select only equipment you have confirmed. Nothing is preselected.")
                }
                Section {
                    TextField("One machine per line", text: $machines, axis: .vertical).lineLimit(3...8)
                } header: {
                    Text("Preferred machines (optional)")
                } footer: {
                    Text("Your own machine names. Preferences do not add equipment to the inventory.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .navigationTitle(gym == nil ? "Add gym" : "Edit gym")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }.accessibilityIdentifier("gym_save")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        do {
            try save(Gym(
                id: gym?.id ?? UUID(), name: name, coarseRegion: region, equipment: equipment,
                preferredMachines: machines.split(separator: "\n").map(String.init)
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GymExerciseLibraryView: View {
    @ObservedObject var registry: GymRegistry
    let accessToken: () async -> String?
    let isCurrent: () -> Bool
    @State private var exercises: [GymLibraryExercise] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage)
                    Button("Try again") { Task { await load() } }
                } else if exercises.isEmpty {
                    Text("No exercises match this equipment.")
                } else {
                    ForEach(exercises) { Text($0.name) }
                }
            } header: {
                Text(registry.activeGym?.name ?? "All equipment allowed")
            }
        }
        .navigationTitle("Exercises")
        .task(id: registry.equipmentFilter) { await load() }
    }

    private func load() async {
        isLoading = true
        exercises = []
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard isCurrent(), let token = await accessToken(), isCurrent() else { throw GymRegistryError.accountChanged }
            let result = try await registry.exercises(accessToken: token, isCurrent: isCurrent)
            guard !Task.isCancelled else { return }
            exercises = result
        } catch {
            if isCurrent(), !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
