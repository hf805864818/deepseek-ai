//
//  SessionEditSheet.swift
//  Minis - home screen (session list, navigation, settings entry)
//
//  Edit a session's title and category; SpinningRing is shared with the rows
//  and section headers.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Session Edit Sheet

struct SessionEditSheet: View {
    let session: ChatSession
    let onSave: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editTitle: String = ""
    @State private var editCategory: String = ""
    @State private var isRegenerating = false
    @StateObject private var profileStore = EnvProfileStore.shared
    @State private var selectedProfileId: String?

    private static let categories: [(key: String, label: String, icon: String, color: Color)] = [
        ("code",         "Code",         "terminal.fill",               .orange),
        ("writing",      "Writing",      "doc.text.fill",               .blue),
        ("research",     "Research",     "globe.americas.fill",         .teal),
        ("analysis",     "Analysis",     "chart.pie.fill",              .indigo),
        ("creative",     "Creative",     "paintbrush.pointed.fill",     .pink),
        ("chat",         "Chat",         "bubble.left.fill",            .green),
        ("math",         "Math",         "number.circle.fill",          .purple),
        ("translation",  "Translation",  "character.bubble",            .cyan),
        ("health",       "Health",       "heart.fill",                  .red),
        ("finance",      "Finance",      "banknote.fill",               .mint),
        ("travel",       "Travel",       "map.fill",                    .orange),
        ("education",    "Education",    "book.closed.fill",            .blue),
        ("design",       "Design",       "paintpalette.fill",           .pink),
        ("productivity", "Productivity", "calendar.badge.checkmark",    .yellow),
        ("support",      "Support",      "gearshape.fill",              .brown),
        ("other",        "Other",        "square.grid.2x2.fill",       .gray),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Title") {
                    TextField("Session title", text: $editTitle)
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(Self.categories, id: \.key) { cat in
                            Button {
                                editCategory = cat.key
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(editCategory == cat.key ? .white : cat.color)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(editCategory == cat.key ? cat.color : cat.color.opacity(0.12))
                                        )
                                    Text(LocalizedStringKey(cat.label))
                                        .font(.caption2)
                                        .foregroundStyle(editCategory == cat.key ? cat.color : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // [T-fork-env-profile-restore] Environment Profile picker
                // (restored after the source merge dropped it). Pins this
                // session to a specific env-var profile; nil = global only.
                Section("Environment Profile") {
                    Menu {
                        Button {
                            selectedProfileId = nil
                        } label: {
                            HStack {
                                if selectedProfileId == nil {
                                    Image(systemName: "checkmark")
                                }
                                Text("None (Global only)")
                            }
                        }
                        ForEach(profileStore.profiles) { profile in
                            Button {
                                selectedProfileId = profile.id
                            } label: {
                                HStack {
                                    if selectedProfileId == profile.id {
                                        Image(systemName: "checkmark")
                                    }
                                    Image(systemName: profile.icon ?? "square.stack.3d.up")
                                    Text(profile.name)
                                    if profile.isDefault {
                                        Text("Default")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        profileMenuLabel
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button {
                        regenerate()
                    } label: {
                        HStack {
                            if isRegenerating {
                                SpinningRing(color: .accentColor)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Regenerate Title")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(isRegenerating)
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        onSave(title, editCategory.isEmpty ? nil : editCategory, selectedProfileId)
                    }
                    .bold()
                    .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                editTitle = session.title ?? ""
                editCategory = session.category ?? ""
                selectedProfileId = session.envProfileId
            }
        }
    }

    @ViewBuilder
    private var profileMenuLabel: some View {
        HStack {
            if let profile = profileStore.profiles.first(where: { $0.id == selectedProfileId }) {
                profileIconView(profile)
                profileNameView(profile)
            } else {
                noProfileView
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func profileIconView(_ profile: EnvProfile) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: profile.icon ?? "square.stack.3d.up")
                .font(.system(size: 13))
                .foregroundStyle(.accent)
        }
    }

    @ViewBuilder
    private func profileNameView(_ profile: EnvProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.body)
                if profile.isDefault {
                    Text("Default")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var noProfileView: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        Text("None (Global only)")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func regenerate() {
        guard !isRegenerating else { return }
        isRegenerating = true
        Task { @MainActor in
            defer { isRegenerating = false }
            do {
                try await AIChatViewModel.regenerateSessionTitle(sessionId: session.id)
                if let updated = await ChatStore.shared.getSession(session.id) {
                    if let title = updated.title { editTitle = title }
                    editCategory = updated.category ?? editCategory
                }
            } catch {
                AppLogger(category: "RegenerateTitle").error(
                    "session=\(session.id) failed: \(error.localizedDescription) — \(String(describing: error))"
                )
            }
        }
    }
}

/// A self-contained spinning arc that uses TimelineView to avoid
/// stacking animations on repeated onAppear calls.
struct SpinningRing: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 1.0) * 360
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }
}
