import SwiftUI
import SafariServices

// MARK: - Google Drive Sync View

/// Settings view for Google Drive sync: account, backup/restore,
/// auto-sync toggle, and backup history list.
@available(iOS 17.0, *)
struct GoogleDriveSyncView: View {

    @ObservedObject private var oauthManager = GoogleDriveOAuthManager.shared
    @ObservedObject private var syncManager = GoogleDriveSyncManager.shared

    // MARK: - View State

    @State private var backups: [GoogleDriveFile] = []
    @State private var isLoadingBackups = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showRestoreConfirm = false
    @State private var restoreFileId: String?
    @State private var restoreFileName: String?

    // MARK: - Body

    var body: some View {
        List {
            accountSection
            if oauthManager.isAuthenticated {
                syncSection
                autoSyncSection
                backupsSection
            }
        }
        .navigationTitle("Google Drive")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if oauthManager.isAuthenticated {
                loadBackups()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Restore Backup?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                if let fileId = restoreFileId {
                    performRestore(from: fileId)
                }
            }
        } message: {
            if let name = restoreFileName {
                Text("This will overwrite files in the app's documents directory with the contents of \"\(name)\". This cannot be undone.")
            }
        }
        .onChange(of: syncManager.syncError) { _, error in
            if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            if oauthManager.isAuthenticated {
                HStack {
                    settingsIcon("person.crop.circle.fill", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed In")
                            .font(.subheadline)
                        if let email = oauthManager.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        oauthManager.logout()
                        backups = []
                    } label: {
                        Text("Sign Out")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            } else {
                Button {
                    performLogin()
                } label: {
                    HStack {
                        settingsIcon("person.badge.plus", color: .blue)
                        if oauthManager.isAuthenticating {
                            Text("Signing In...")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Sign in with Google")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(oauthManager.isAuthenticating)
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            if let date = syncManager.lastSyncDate {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Backups")
                Spacer()
                Text("\(syncManager.backupCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Total Size")
                Spacer()
                Text(formatSize(syncManager.totalBackupSize))
                    .foregroundStyle(.secondary)
            }
            Button {
                performBackup()
            } label: {
                HStack {
                    settingsIcon("arrow.up.circle.fill", color: .blue)
                    if syncManager.isSyncing {
                        Text("Backing Up...")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Backup Now")
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSyncing)

            Button {
                performRestoreLatest()
            } label: {
                HStack {
                    settingsIcon("arrow.down.circle.fill", color: .green)
                    if syncManager.isSyncing {
                        Text("Restoring...")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore from Latest")
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSyncing)
        } header: {
            Text("Sync")
        }
    }

    // MARK: - Auto Sync Section

    private var autoSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { syncManager.isAutoSyncEnabled },
                set: { newValue in
                    syncManager.isAutoSyncEnabled = newValue
                    if newValue {
                        syncManager.startAutoSync()
                    } else {
                        syncManager.stopAutoSync()
                    }
                }
            )) {
                HStack {
                    settingsIcon("arrow.triangle.2.circlepath", color: .orange)
                    Text("Auto Sync")
                }
            }
        } header: {
            Text("Auto Sync")
        } footer: {
            Text("Automatically backs up your data to Google Drive every 4 hours when the app is running.")
        }
    }

    // MARK: - Backups Section

    private var backupsSection: some View {
        Section {
            if isLoadingBackups {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading backups...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if backups.isEmpty {
                Text("No backups yet. Tap \"Backup Now\" to create one.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(backups, id: \.id) { backup in
                    Button {
                        restoreFileId = backup.id
                        restoreFileName = backup.name
                        showRestoreConfirm = true
                    } label: {
                        HStack {
                            settingsIcon("doc.zipper", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    if let date = backup.modifiedTime {
                                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if let size = backup.size {
                                        Text(formatSize(size))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.uturn.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(syncManager.isSyncing)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            performDelete(fileId: backup.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Backups")
        }
    }

    // MARK: - Actions

    private func performLogin() {
        Task {
            do {
                try await oauthManager.login()
                await loadBackups()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performBackup() {
        Task {
            do {
                try await syncManager.backup()
                await loadBackups()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performRestoreLatest() {
        Task {
            do {
                try await syncManager.restore()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performRestore(from fileId: String) {
        Task {
            do {
                try await syncManager.restoreFrom(fileId: fileId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performDelete(fileId: String) {
        Task {
            do {
                try await syncManager.deleteBackup(fileId: fileId)
                await loadBackups()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Data Loading

    private func loadBackups() {
        isLoadingBackups = true
        Task {
            do {
                backups = try await syncManager.listBackups()
            } catch {
                // Silently ignore — the list will just be empty
            }
            isLoadingBackups = false
        }
    }

    // MARK: - Helpers

    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .frame(width: 21, height: 21)
            .background(color, in: Circle())
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }
}
