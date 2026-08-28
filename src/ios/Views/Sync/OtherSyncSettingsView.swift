import SwiftUI

// MARK: - Other Sync Settings View

/// Lists all available cloud sync platforms. Each platform has an icon,
/// name, and connection status. Local Sync and Google Drive are implemented;
/// OneDrive and WebDAV are placeholders for future support.
@available(iOS 17.0, *)
struct OtherSyncSettingsView: View {

    @ObservedObject private var oauthManager = GoogleDriveOAuthManager.shared
    @ObservedObject private var localSyncManager = LocalSyncManager.shared

    var body: some View {
        List {
            // MARK: Local Sync

            NavigationLink(destination: LocalSyncView()) {
                platformRow(
                    icon: "tray.and.arrow.down.fill",
                    color: .green,
                    name: String(localized: "Local Sync", comment: "Local sync platform name"),
                    status: localSyncManager.hasDestination ? .connected : .disconnected
                )
            }
            .buttonStyle(.plain)

            // MARK: Google Drive

            NavigationLink(destination: GoogleDriveSyncView()) {
                platformRow(
                    icon: "externaldrive.fill",
                    color: .blue,
                    name: "Google Drive",
                    status: oauthManager.isAuthenticated ? .connected : .disconnected
                )
            }
            .buttonStyle(.plain)

            // MARK: OneDrive (Coming Soon)

            platformRow(
                icon: "externaldrive.fill",
                color: .blue,
                name: "OneDrive",
                status: .comingSoon
            )

            // MARK: WebDAV (Coming Soon)

            platformRow(
                icon: "server.rack",
                color: .gray,
                name: "WebDAV",
                status: .comingSoon
            )
        }
        .navigationTitle(String(localized: "Other Sync", comment: "Navigation title for third-party cloud sync settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Platform Row

    private enum PlatformStatus {
        case connected
        case disconnected
        case comingSoon
    }

    @ViewBuilder
    private func platformRow(
        icon: String,
        color: Color,
        name: String,
        status: PlatformStatus
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, color: color)
            Text(name)
            Spacer()
            statusBadge(status)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PlatformStatus) -> some View {
        switch status {
        case .connected:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Connected")
            }
            .foregroundStyle(.green)
            .font(.caption)
        case .disconnected:
            HStack(spacing: 4) {
                Image(systemName: "circle")
                Text("Not Connected")
            }
            .foregroundStyle(.secondary)
            .font(.caption)
        case .comingSoon:
            Text("Coming Soon")
                .foregroundStyle(.secondary)
                .font(.caption)
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
}
