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
        .navigationTitle(AppLocalized("Google Drive", comment: "Navigation title for Google Drive sync settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if oauthManager.isAuthenticated {
                loadBackups()
            }
        }
        .alert(AppLocalized("Error", comment: "Error alert title"), isPresented: $showError) {
            Button(AppLocalized("OK", comment: "Error alert confirm button"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? AppLocalized("An unknown error occurred.", comment: "Generic error message"))
        }
        .alert(AppLocalized("Restore Backup?", comment: "Restore confirmation alert title"), isPresented: $showRestoreConfirm) {
            Button(AppLocalized("Cancel", comment: "Restore confirmation cancel button"), role: .cancel) {}
            Button(AppLocalized("Restore", comment: "Restore confirmation confirm button")) {
                if let fileId = restoreFileId {
                    performRestore(from: fileId)
                } else {
                    performRestoreLatest()
                }
            }
        } message: {
            if let name = restoreFileName {
                Text(String.localizedStringWithFormat(
                    AppLocalized("This will overwrite files in the app's documents directory with the contents of \"%@\". This cannot be undone.",
                           comment: "Restore confirmation message with file name"),
                    name
                ))
            }
        }
        .onChange(of: syncManager.syncError) { _, error in
            if let error = error {
                errorMessage = error
                showError = true
            }
        }
        // Refresh the backup list when a backup completes (isBackingUp
        // falls true → false). backup() is fire-and-forget, so the list
        // must be reloaded here rather than right after backup() returns.
        .onChange(of: syncManager.isBackingUp) { wasBackingUp, isBackingUp in
            if wasBackingUp && !isBackingUp {
                loadBackups()
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
                        Text(AppLocalized("Signed In", comment: "Google Drive signed in status"))
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
                        Text(AppLocalized("Sign Out", comment: "Google Drive sign out button"))
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
                            Text(AppLocalized("Signing In...", comment: "Google Drive signing in status"))
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(AppLocalized("Sign in with Google", comment: "Google Drive sign in button"))
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
            Text(AppLocalized("Account", comment: "Google Drive account section header"))
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            if let date = syncManager.lastSyncDate {
                HStack {
                    Text(AppLocalized("Last Synced", comment: "Last sync time label"))
                    Spacer()
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(AppLocalized("Backups", comment: "Backup count label"))
                Spacer()
                Text("\(syncManager.backupCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(AppLocalized("Total Size", comment: "Total backup size label"))
                Spacer()
                Text(formatSize(syncManager.totalBackupSize))
                    .foregroundStyle(.secondary)
            }
            Button {
                performBackup()
            } label: {
                HStack {
                    settingsIcon("arrow.up.circle.fill", color: .blue)
                    if syncManager.isBackingUp {
                        Text(AppLocalized("Backing Up...", comment: "Backup in progress status"))
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(AppLocalized("Backup Now", comment: "Backup now button"))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isBackingUp || syncManager.isRestoring)

            Button {
                confirmRestoreLatest()
            } label: {
                HStack {
                    settingsIcon("arrow.down.circle.fill", color: .green)
                    if syncManager.isRestoring {
                        Text(AppLocalized("Restoring...", comment: "Restore in progress status"))
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(AppLocalized("Restore from Latest", comment: "Restore from latest backup button"))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isBackingUp || syncManager.isRestoring)
        } header: {
            Text(AppLocalized("Sync", comment: "Google Drive sync section header"))
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
                    Text(AppLocalized("Auto Sync", comment: "Auto sync toggle label"))
                }
            }
        } header: {
            Text(AppLocalized("Auto Sync", comment: "Auto sync section header"))
        } footer: {
            Text(AppLocalized("Automatically backs up your data to Google Drive every 4 hours when the app is running.",
                         comment: "Auto sync description footer"))
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
                    Text(AppLocalized("Loading backups...", comment: "Loading backups status"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if backups.isEmpty {
                Text(AppLocalized("No backups yet. Tap \"Backup Now\" to create one.",
                             comment: "Empty backups state message"))
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
                    .disabled(syncManager.isBackingUp || syncManager.isRestoring)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            performDelete(fileId: backup.id)
                        } label: {
                            Label(AppLocalized("Delete", comment: "Delete backup swipe action"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(AppLocalized("Backups", comment: "Backups list section header"))
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
            // backup() is fire-and-forget (to avoid blocking MainActor), so
            // it returns before the upload completes. Refreshing the list
            // here would show a stale list — the actual refresh happens via
            // the onChange(of: isBackingUp) modifier when the flag falls.
            await syncManager.backup()
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

    /// Shows the restore confirmation alert for "Restore from Latest".
    /// Reuses the per-file restore alert by leaving `restoreFileId` nil;
    /// the alert's Restore button falls back to `performRestoreLatest()`.
    private func confirmRestoreLatest() {
        restoreFileId = nil
        restoreFileName = AppLocalized("the latest backup", comment: "Restore latest confirmation name")
        showRestoreConfirm = true
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
            return String.localizedStringWithFormat(
                AppLocalized("%.1f GB", comment: "Gigabytes size format"),
                Double(bytes) / 1_073_741_824
            )
        } else if bytes >= 1_048_576 {
            return String.localizedStringWithFormat(
                AppLocalized("%.1f MB", comment: "Megabytes size format"),
                Double(bytes) / 1_048_576
            )
        } else if bytes >= 1024 {
            return String.localizedStringWithFormat(
                AppLocalized("%.1f KB", comment: "Kilobytes size format"),
                Double(bytes) / 1024
            )
        } else {
            return String.localizedStringWithFormat(
                AppLocalized("%lld B", comment: "Bytes size format"),
                bytes
            )
        }
    }
}
