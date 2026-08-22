//
//  UpdateCheckRow.swift
//  Minis
//
//  Settings / About row that checks for app updates and surfaces
//  a TrollStore-powered install flow (with Safari fallback).
//

import SwiftUI
import UIKit

/// A settings row + dialog pair for checking and installing app updates.
///
/// Place this inside a List Section. It owns its own state, performs
/// network checks via UpdateChecker, and presents a modal sheet when
/// an update is available.
struct UpdateCheckRow: View {

    // MARK: - State

    @State private var isChecking = false
    @State private var statusMessage: String? = nil
    @State private var showReleasesLink = false
    @State private var showUpdateDialog = false
    @State private var updateVersion: String? = nil
    @State private var updateIPAURL: URL? = nil
    @State private var updateChangelog: String = ""

    // MARK: - Current Version

    private let currentVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()

    // MARK: - Body

    var body: some View {
        Section {
            // Check for Updates row
            Button {
                Task { await performCheck() }
            } label: {
                HStack {
                    Label {
                        HStack {
                            Text(isChecking
                                 ? NSLocalizedString("Checking for Updates…", comment: "Update check in progress")
                                 : NSLocalizedString("Check for Updates", comment: "Update check button title"))
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            if isChecking {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .disabled(isChecking)
            .buttonStyle(.plain)

            // Status message (up-to-date, error, etc.)
            if let status = statusMessage, !showUpdateDialog {
                HStack {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(statusColor(for: status))
                    Spacer()
                }
                .padding(.leading, 40) // align with label text
                .listRowBackground(Color.clear)
            }

            // Releases page link (for geo-blocked / forbidden cases)
            if showReleasesLink {
                Button {
                    UpdateChecker.shared.openReleasesPage()
                } label: {
                    HStack {
                        Text(NSLocalizedString("Open GitHub Releases", comment: "Fallback link when API is blocked"))
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 40)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text(NSLocalizedString("Update", comment: "Update section header"))
        } footer: {
            Text(String(format: NSLocalizedString("Current Version %@", comment: "Current version footer"),
                        currentVersion))
        }
        .sheet(isPresented: $showUpdateDialog) {
            UpdateDialogView(
                version: updateVersion ?? "",
                currentVersion: currentVersion,
                changelog: updateChangelog,
                ipaURL: updateIPAURL,
                onDismiss: {
                    showUpdateDialog = false
                    // Mark as dismissed so the badge goes away.
                    if let v = updateVersion {
                        UpdateChecker.shared.dismissedVersion = v
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private func performCheck() async {
        isChecking = true
        statusMessage = nil
        showReleasesLink = false

        let result = await UpdateChecker.shared.check()

        switch result {
        case .updateAvailable(let version, let ipaURL, let changelog):
            updateVersion = version
            updateIPAURL = ipaURL
            updateChangelog = changelog
            statusMessage = String(format: NSLocalizedString("New version available: %@", comment: "New version found status"), version)
            // Update persisted state.
            UpdateChecker.shared.hasPendingUpdate = true
            UpdateChecker.shared.pendingVersion = version
            UpdateChecker.shared.pendingIPAURL = ipaURL
            UpdateChecker.shared.pendingChangelog = changelog
            // Show dialog after a short delay so the user sees the status.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showUpdateDialog = true
            }

        case .upToDate:
            statusMessage = NSLocalizedString("You're up to date", comment: "No update available")
            UpdateChecker.shared.hasPendingUpdate = false
            UpdateChecker.shared.pendingVersion = nil
            UpdateChecker.shared.pendingIPAURL = nil
            UpdateChecker.shared.pendingChangelog = nil

        case .noReleaseAvailable:
            statusMessage = NSLocalizedString("No releases found", comment: "No releases available")

        case .noIPAAsset(let version):
            statusMessage = String(format: NSLocalizedString("Version %@ has no IPA", comment: "New version but no IPA asset"), version)

        case .forbidden:
            statusMessage = NSLocalizedString("Unable to check (network restricted)", comment: "Geo-blocked / 403 error")
            showReleasesLink = true

        case .networkUnreachable:
            statusMessage = NSLocalizedString("Network unavailable", comment: "No internet connection")

        case .error(let message):
            statusMessage = String(format: NSLocalizedString("Check failed: %@", comment: "Generic check error"), message)
        }

        isChecking = false
    }

    // MARK: - Helpers

    private func statusColor(for message: String) -> Color {
        if message.lowercased().contains("up to date") ||
            message.contains("最新") || message.contains("up-to-date") {
            return .green
        }
        if message.lowercased().contains("new version") ||
            message.contains("新版本") {
            return .blue
        }
        if message.lowercased().contains("failed") ||
            message.lowercased().contains("unable") ||
            message.lowercased().contains("unavailable") ||
            message.contains("失败") || message.contains("无法") {
            return .red
        }
        return .secondary
    }
}

// MARK: - Update Dialog

private struct UpdateDialogView: View {

    let version: String
    let currentVersion: String
    let changelog: String
    let ipaURL: URL?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text(NSLocalizedString("New Version Available", comment: "Update dialog title"))
                            .font(.title2.bold())
                        Text(String(format: NSLocalizedString("%@ → %@", comment: "Version transition in update dialog"),
                                    currentVersion, version))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Changelog
                    if !changelog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("What's New", comment: "Changelog header").uppercased())
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Text(changelog)
                                .font(.subheadline)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(UIColor.secondarySystemBackground))
                                )
                        }
                    }

                    // Install hint
                    VStack(spacing: 6) {
                        if UpdateChecker.shared.hasTrollStore {
                            Label {
                                Text(NSLocalizedString("Tap Update to install via TrollStore",
                                                      comment: "TrollStore install hint"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Label {
                                Text(NSLocalizedString("TrollStore not found — will open Releases page",
                                                      comment: "No TrollStore fallback hint"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Update Now", comment: "Update action button")) {
                        handleUpdate()
                    }
                    .font(.headline)
                    .disabled(ipaURL == nil)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleUpdate() {
        guard let ipaURL = ipaURL else { return }

        if UpdateChecker.shared.hasTrollStore {
            let ok = UpdateChecker.shared.installViaTrollStore(ipaURL: ipaURL)
            if !ok {
                // Fallback: open releases page.
                UpdateChecker.shared.openReleasesPage()
            }
        } else {
            UpdateChecker.shared.openReleasesPage()
        }

        dismiss()
        onDismiss()
    }
}

// MARK: - Preview

#Preview {
    List {
        UpdateCheckRow()
    }
    .listStyle(.insetGrouped)
}
