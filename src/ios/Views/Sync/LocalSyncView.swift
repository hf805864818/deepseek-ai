import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Folder Picker

/// Wraps `UIDocumentPickerViewController` to let the user pick a directory
/// in the Files app. The resulting URL is security-scoped; persistent
/// access is kept by storing a security-scoped bookmark
/// (see `LocalSyncManager.saveDestination`).
private struct FolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(_ parent: FolderPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            if let url = urls.first {
                parent.onPick(url)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Local Sync View

/// Settings view for local directory sync: destination folder selection,
/// backup/restore, auto-sync toggle, and backup history list.
///
/// The backup flow uses fire-and-forget (like `GoogleDriveSyncView`), so
/// the backup list is refreshed by observing `isBackingUp` falling back to
/// false — NOT by calling `loadBackups()` immediately after `backup()`
/// (which would run before the write completes and show a stale list).
@available(iOS 17.0, *)
struct LocalSyncView: View {

    @ObservedObject private var syncManager = LocalSyncManager.shared

    // MARK: - View State

    @State private var backups: [LocalBackup] = []
    @State private var isLoadingBackups = false
    @State private var showFolderPicker = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showRestoreConfirm = false
    @State private var restoreBackup: LocalBackup?

    // MARK: - Body

    var body: some View {
        List {
            destinationSection
            if syncManager.hasDestination {
                syncSection
                autoSyncSection
                backupsSection
            }
        }
        .navigationTitle(String(localized: "Local Sync", comment: "Navigation title for local sync settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if syncManager.hasDestination {
                loadBackups()
            }
        }
        .alert(String(localized: "Error", comment: "Error alert title"), isPresented: $showError) {
            Button(String(localized: "OK", comment: "Error alert confirm button"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "An unknown error occurred.", comment: "Generic error message"))
        }
        .alert(String(localized: "Restore Backup?", comment: "Restore confirmation alert title"), isPresented: $showRestoreConfirm) {
            Button(String(localized: "Cancel", comment: "Restore confirmation cancel button"), role: .cancel) {}
            Button(String(localized: "Restore", comment: "Restore confirmation confirm button")) {
                if let backup = restoreBackup {
                    performRestore(from: backup)
                }
            }
        } message: {
            if let backup = restoreBackup {
                Text(String.localizedStringWithFormat(
                    String(localized: "This will overwrite files in the app's documents directory with the contents of \"%@\". This cannot be undone.",
                           comment: "Restore confirmation message with file name"),
                    backup.name
                ))
            }
        }
        // Surface sync errors surfaced by the manager.
        .onChange(of: syncManager.syncError) { _, error in
            if let error = error {
                errorMessage = error
                showError = true
            }
        }
        // Refresh the backup list when a backup completes (isBackingUp
        // falls true → false). This avoids the stale-list bug that an
        // immediate `loadBackups()` after the fire-and-forget `backup()`
        // would cause.
        .onChange(of: syncManager.isBackingUp) { wasBackingUp, isBackingUp in
            if wasBackingUp && !isBackingUp {
                loadBackups()
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker(isPresented: $showFolderPicker) { url in
                syncManager.saveDestination(url)
                loadBackups()
            }
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        Section {
            if syncManager.hasDestination {
                HStack {
                    settingsIcon("folder.fill", color: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Folder Selected", comment: "Local sync destination selected status"))
                            .font(.subheadline)
                        if let name = syncManager.destinationName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        showFolderPicker = true
                    } label: {
                        Text(String(localized: "Change", comment: "Local sync change folder button"))
                    }
                    .buttonStyle(.plain)
                }
                Button(role: .destructive) {
                    syncManager.clearDestination()
                    backups = []
                } label: {
                    Text(String(localized: "Clear Folder", comment: "Local sync clear folder button"))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showFolderPicker = true
                } label: {
                    HStack {
                        settingsIcon("folder.badge.plus", color: .green)
                        Text(String(localized: "Choose Folder", comment: "Local sync choose folder button"))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(String(localized: "Destination", comment: "Local sync destination section header"))
        } footer: {
            Text(String(localized: "Pick a folder in the Files app. Backups are saved there as ZIP files and persist even if the app is uninstalled.",
                         comment: "Local sync destination footer"))
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            if let date = syncManager.lastSyncDate {
                HStack {
                    Text(String(localized: "Last Synced", comment: "Last sync time label"))
                    Spacer()
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(String(localized: "Backups", comment: "Backup count label"))
                Spacer()
                Text("\(syncManager.backupCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "Total Size", comment: "Total backup size label"))
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
                        Text(String(localized: "Backing Up...", comment: "Backup in progress status"))
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Backup Now", comment: "Backup now button"))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isBackingUp || syncManager.isRestoring)

            Button {
                performRestoreLatest()
            } label: {
                HStack {
                    settingsIcon("arrow.down.circle.fill", color: .green)
                    if syncManager.isRestoring {
                        Text(String(localized: "Restoring...", comment: "Restore in progress status"))
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Restore from Latest", comment: "Restore from latest backup button"))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isBackingUp || syncManager.isRestoring)
        } header: {
            Text(String(localized: "Sync", comment: "Local sync section header"))
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
                    Text(String(localized: "Auto Sync", comment: "Auto sync toggle label"))
                }
            }
        } header: {
            Text(String(localized: "Auto Sync", comment: "Auto sync section header"))
        } footer: {
            Text(String(localized: "Automatically backs up your data to the selected folder every 4 hours when the app is running.",
                         comment: "Local auto sync description footer"))
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
                    Text(String(localized: "Loading backups...", comment: "Loading backups status"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if backups.isEmpty {
                Text(String(localized: "No backups yet. Tap \"Backup Now\" to create one.",
                             comment: "Empty backups state message"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(backups) { backup in
                    Button {
                        restoreBackup = backup
                        showRestoreConfirm = true
                    } label: {
                        HStack {
                            settingsIcon("doc.zipper", color: .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(backup.modifiedDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(formatSize(backup.size))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
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
                            performDelete(backup)
                        } label: {
                            Label(String(localized: "Delete", comment: "Delete backup swipe action"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "Backups", comment: "Backups list section header"))
        }
    }

    // MARK: - Actions

    private func performBackup() {
        Task {
            // Fire-and-forget backup; the list is refreshed via the
            // onChange(of: isBackingUp) modifier above.
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

    private func performRestore(from backup: LocalBackup) {
        Task {
            do {
                try await syncManager.restoreFrom(url: backup.url)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performDelete(_ backup: LocalBackup) {
        Task {
            do {
                try await syncManager.deleteBackup(at: backup.url)
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
                // Silently ignore — the list will just be empty.
                backups = []
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
                String(localized: "%.1f GB", comment: "Gigabytes size format"),
                Double(bytes) / 1_073_741_824
            )
        } else if bytes >= 1_048_576 {
            return String.localizedStringWithFormat(
                String(localized: "%.1f MB", comment: "Megabytes size format"),
                Double(bytes) / 1_048_576
            )
        } else if bytes >= 1024 {
            return String.localizedStringWithFormat(
                String(localized: "%.1f KB", comment: "Kilobytes size format"),
                Double(bytes) / 1024
            )
        } else {
            return String.localizedStringWithFormat(
                String(localized: "%lld B", comment: "Bytes size format"),
                bytes
            )
        }
    }
}
