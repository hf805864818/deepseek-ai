import SwiftUI
import UIKit

// MARK: - Env Profile List View

/// Displays the list of env var profiles. Shown as a sub-page within
/// EnvironmentVariablesView when the "Profiles" tab is selected.
struct EnvProfileListView: View {
    @StateObject private var store = EnvProfileStore.shared
    @State private var showingAddSheet = false
    @State private var editingProfile: EnvProfile?
    @State private var profileToDelete: EnvProfile?
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            if store.profiles.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Profiles")
                            .font(.headline)
                        Text("Create profiles to group env vars by account or project. Sessions can switch between profiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach(store.profiles) { profile in
                        profileRow(profile)
                    }
                    .onDelete(perform: deleteProfiles)
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Each profile can override global env vars. Assign a profile to a session to use its values.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Env Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            EnvProfileFormSheet(mode: .add) { name, icon, isDefault in
                store.addProfile(name: name, icon: icon, isDefault: isDefault)
            }
        }
        .sheet(item: $editingProfile) { profile in
            EnvProfileFormSheet(
                mode: .edit,
                initialName: profile.name,
                initialIcon: profile.icon,
                initialIsDefault: profile.isDefault
            ) { name, icon, isDefault in
                store.updateProfile(id: profile.id, name: name, icon: icon, color: nil, isDefault: isDefault)
            } onDelete: {
                profileToDelete = profile
                showingDeleteConfirm = true
            }
        }
        .alert(
            "Delete profile?",
            isPresented: $showingDeleteConfirm,
            presenting: profileToDelete
        ) { profile in
            Button("Delete", role: .destructive) {
                store.deleteProfile(id: profile.id)
                editingProfile = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("All env vars in \"\(profile.name)\" will be deleted. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: EnvProfile) -> some View {
        let count = store.vars(for: profile.id).count
        NavigationLink {
            EnvProfileVarsView(profile: profile)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: profile.icon ?? "square.stack.3d.up")
                        .font(.system(size: 16))
                        .foregroundStyle(.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.body)
                            .fontWeight(.medium)
                        if profile.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(count) variable\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editingProfile = profile
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let profilesToDelete = offsets.map { store.profiles[$0] }
        for profile in profilesToDelete {
            store.deleteProfile(id: profile.id)
        }
    }
}

// MARK: - Profile Vars Detail View

/// Shows env vars within a specific profile. Similar layout to the
/// global EnvironmentVariablesView but scoped to one profile.
struct EnvProfileVarsView: View {
    @StateObject private var store = EnvProfileStore.shared
    let profile: EnvProfile

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingEntry: EnvProfileVar?
    @State private var revealedKeys: Set<String> = []
    @State private var copiedId: String?

    private var filteredEntries: [EnvProfileVar] {
        let entries = store.vars(for: profile.id)
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: profile.icon ?? "square.stack.3d.up")
                        .foregroundStyle(.accent)
                    Text(profile.name)
                        .font(.headline)
                    if profile.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(.accent)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }

            if filteredEntries.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Variables")
                            .font(.headline)
                        Text("Add env vars to this profile. They override global vars with the same name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ForEach(filteredEntries) { entry in
                    envVarRow(entry)
                }
                .onDelete(perform: deleteEntries)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Variables")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter by name")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            EnvVarFormSheet(mode: .add) { key, value, note in
                store.addVar(to: profile.id, key: key, value: value, note: note)
            }
        }
        .sheet(item: $editingEntry) { entry in
            EnvVarFormSheet(
                mode: .edit,
                initialKey: entry.key,
                initialValue: store.value(for: profile.id, key: entry.key) ?? "",
                initialNote: entry.note
            ) { key, value, note in
                store.updateVar(id: entry.id, key: key, value: value, note: note)
            } onDelete: {
                store.deleteVar(id: entry.id)
            }
        }
    }

    @ViewBuilder
    private func envVarRow(_ entry: EnvProfileVar) -> some View {
        let isRevealed = revealedKeys.contains(entry.id)
        let currentValue = store.value(for: profile.id, key: entry.key) ?? ""

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.key)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(isRevealed ? currentValue : String(repeating: "\u{2022}", count: min(currentValue.count, 20)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    if isRevealed {
                        revealedKeys.remove(entry.id)
                    } else {
                        revealedKeys.insert(entry.id)
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = "\(entry.key)=\(currentValue)"
                    withAnimation { copiedId = entry.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { if copiedId == entry.id { copiedId = nil } }
                    }
                } label: {
                    Image(systemName: copiedId == entry.id ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 13))
                        .foregroundStyle(copiedId == entry.id ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingEntry = entry
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let entriesToDelete = offsets.map { filteredEntries[$0] }
        for entry in entriesToDelete {
            store.deleteVar(id: entry.id)
        }
    }
}

// MARK: - Profile Form Sheet

struct EnvProfileFormSheet: View {
    enum Mode { case add, edit }

    let mode: Mode
    var initialName: String = ""
    var initialIcon: String? = nil
    var initialIsDefault: Bool = false
    let onSave: (String, String?, Bool) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon: String = ""
    @State private var isDefault = false
    @State private var showingDeleteConfirm = false
    @FocusState private var focusedField: Bool

    private let iconOptions = [
        "briefcase", "person", "house", "building.2",
        "desktopcomputer", "laptopcomputer", "server.rack",
        "hammer", "wrench.and.screwdriver", "flask",
        "atom", "bolt", "star", "heart", "tag"
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                        .focused($focusedField)
                        .submitLabel(.done)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(iconOptions, id: \.self) { sfName in
                                Button {
                                    icon = sfName
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(icon == sfName ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .stroke(icon == sfName ? Color.accentColor : .clear, lineWidth: 2)
                                            )
                                        Image(systemName: sfName)
                                            .font(.system(size: 18))
                                            .foregroundStyle(icon == sfName ? .accent : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Toggle("Default for new sessions", isOn: $isDefault)
                } footer: {
                    Text("New sessions will automatically use this profile. You can override per-session in chat settings.")
                }

                if mode == .edit, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label {
                                Text("Delete Profile")
                            } icon: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white)
                                    .frame(width: 21, height: 21)
                                    .background(.red, in: Circle())
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .add ? "Create" : "Save") {
                        let selectedIcon = icon.isEmpty ? nil : icon
                        onSave(name, selectedIcon, isDefault)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .alert(
                "Delete this profile?",
                isPresented: $showingDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All env vars in this profile will be deleted. This cannot be undone.")
            }
            .onAppear {
                name = initialName
                icon = initialIcon ?? ""
                isDefault = initialIsDefault
            }
            .task {
                // Wait for sheet animation to settle before focusing
                try? await Task.sleep(nanoseconds: 400_000_000)
                if mode == .add {
                    focusedField = true
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
