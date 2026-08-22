//
//  UpdateChecker.swift
//  Minis
//
//  Checks for new app versions via GitHub Releases API and supports
//  installation through TrollStore (apple-magnifier:// URL scheme).
//

import Foundation
import UIKit

/// Checks for app updates from GitHub Releases and provides
/// TrollStore-based installation on supported devices.
final class UpdateChecker {

    // MARK: - Shared

    static let shared = UpdateChecker()

    private init() {}

    // MARK: - Configuration

    private static let repoOwner = "vbox-Ai"
    private static let repoName = "Lobster-APP"
    private static let apiURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=30"
    static let releasesURL = "https://github.com/\(repoOwner)/\(repoName)/releases"

    /// Minimum interval between automatic checks (24 hours).
    private static let autoCheckInterval: TimeInterval = 86_400

    // MARK: - UserDefaults Keys

    private enum Key {
        static let lastCheckDate      = "update_check_last_date"
        static let hasPendingUpdate   = "update_check_has_pending"
        static let pendingVersion     = "update_check_pending_version"
        static let pendingIPAURL      = "update_check_pending_ipa_url"
        static let pendingChangelog   = "update_check_pending_changelog"
        static let dismissedVersion   = "update_check_dismissed_version"
    }

    // MARK: - Check Result

    enum CheckResult {
        case updateAvailable(version: String, ipaURL: URL, changelog: String)
        case upToDate
        case noReleaseAvailable
        case noIPAAsset(version: String)
        case forbidden          // 403 / 451 geo-block
        case networkUnreachable
        case error(message: String)
    }

    // MARK: - Current Version

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - TrollStore Detection

    /// Returns true if TrollStore is installed on this device.
    var hasTrollStore: Bool {
        guard let url = URL(string: "apple-magnifier://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - Pending Update State (persisted)

    /// Whether a newer version is available (cached from last check).
    var hasPendingUpdate: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasPendingUpdate) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasPendingUpdate) }
    }

    /// The pending newer version string, if any.
    var pendingVersion: String? {
        get { UserDefaults.standard.string(forKey: Key.pendingVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Key.pendingVersion) }
    }

    /// The IPA download URL for the pending update.
    var pendingIPAURL: URL? {
        get {
            guard let s = UserDefaults.standard.string(forKey: Key.pendingIPAURL) else { return nil }
            return URL(string: s)
        }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: Key.pendingIPAURL) }
    }

    /// Changelog / release body for the pending update.
    var pendingChangelog: String? {
        get { UserDefaults.standard.string(forKey: Key.pendingChangelog) }
        set { UserDefaults.standard.set(newValue, forKey: Key.pendingChangelog) }
    }

    /// Last time a check was performed (used for throttling).
    private var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: Key.lastCheckDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastCheckDate) }
    }

    /// Version the user has explicitly dismissed (won't show badge).
    var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: Key.dismissedVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Key.dismissedVersion) }
    }

    /// Returns true if there is a pending update that the user hasn't dismissed.
    var hasUnreadUpdate: Bool {
        guard hasPendingUpdate, let v = pendingVersion else { return false }
        return dismissedVersion != v
    }

    // MARK: - Automatic Check (launch-time)

    /// Performs a silent background check if enough time has passed.
    /// Does not show any UI — only updates persisted state.
    func checkSilentlyIfNeeded() {
        // Throttle: skip if last check was within the interval.
        if let last = lastCheckDate,
           Date().timeIntervalSince(last) < Self.autoCheckInterval {
            return
        }

        Task {
            let result = await check()
            // Update persisted state regardless of result.
            switch result {
            case .updateAvailable(let version, let ipaURL, let changelog):
                hasPendingUpdate = true
                pendingVersion = version
                pendingIPAURL = ipaURL
                pendingChangelog = changelog
            default:
                // Don't clear pending state on transient errors.
                if case .upToDate = result {
                    hasPendingUpdate = false
                    pendingVersion = nil
                    pendingIPAURL = nil
                    pendingChangelog = nil
                }
            }
            lastCheckDate = Date()
        }
    }

    // MARK: - Manual Check

    /// Performs an immediate check (bypasses throttle) and returns the result.
    @discardableResult
    func check() async -> CheckResult {
        guard let url = URL(string: Self.apiURL) else {
            return .error(message: "Invalid API URL")
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error(message: "Invalid response")
            }

            switch httpResponse.statusCode {
            case 403, 451:
                return .forbidden
            case 200:
                break
            default:
                return .error(message: "HTTP \(httpResponse.statusCode)")
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

            // Filter out drafts.
            let nonDrafts = releases.filter { !($0.draft ?? false) }

            guard !nonDrafts.isEmpty else {
                return .noReleaseAvailable
            }

            // Find the latest release by comparing version numbers.
            guard let latest = nonDrafts.max(by: {
                compareVersions($0.versionTag, $1.versionTag) == .orderedAscending
            }) else {
                return .noReleaseAvailable
            }

            let latestVersion = latest.versionTag

            // Compare with current version.
            switch compareVersions(currentVersion, latestVersion) {
            case .orderedAscending:
                // Newer version available — find IPA asset.
                if let ipaAsset = latest.assets?.first(where: {
                    $0.name.lowercased().hasSuffix(".ipa")
                }), let ipaURL = URL(string: ipaAsset.browser_download_url) {
                    return .updateAvailable(
                        version: latestVersion,
                        ipaURL: ipaURL,
                        changelog: latest.body ?? ""
                    )
                } else {
                    return .noIPAAsset(version: latestVersion)
                }
            case .orderedSame, .orderedDescending:
                return .upToDate
            }

        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain &&
               (nsError.code == NSURLErrorNotConnectedToInternet ||
                nsError.code == NSURLErrorNetworkConnectionLost ||
                nsError.code == NSURLErrorCannotConnectToHost) {
                return .networkUnreachable
            }
            return .error(message: error.localizedDescription)
        }
    }

    // MARK: - Installation

    /// Attempts to install an IPA via TrollStore URL scheme.
    /// Returns false if TrollStore is not available.
    @discardableResult
    func installViaTrollStore(ipaURL: URL) -> Bool {
        guard hasTrollStore else { return false }
        guard let encoded = ipaURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return false
        }
        guard let installURL = URL(string: "apple-magnifier://install?url=\(encoded)") else {
            return false
        }
        UIApplication.shared.open(installURL)
        return true
    }

    /// Opens the GitHub Releases page in Safari (fallback).
    func openReleasesPage() {
        if let url = URL(string: Self.releasesURL) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Version Comparison

    /// Compares two semantic version strings (e.g. "1.0.10" vs "1.0.9").
    /// Handles optional "v" prefix and suffixes like "-preview", "-rc1".
    func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aClean = normalizeVersion(a)
        let bClean = normalizeVersion(b)

        let aParts = aClean.split(separator: ".").compactMap { Int($0) }
        let bParts = bClean.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(aParts.count, bParts.count)

        for i in 0..<maxLen {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal < bVal { return .orderedAscending }
            if aVal > bVal { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Strips leading "v" and trailing pre-release suffixes.
    private func normalizeVersion(_ version: String) -> String {
        var v = version
        if v.hasPrefix("v") {
            v.removeFirst()
        }
        // Strip suffixes like -preview, -rc1, -beta, etc.
        if let range = v.range(of: "-") {
            v = String(v[..<range.lowerBound])
        }
        return v
    }
}

// MARK: - GitHub Release Model

private struct GitHubRelease: Codable {
    let tag_name: String
    let name: String?
    let draft: Bool?
    let prerelease: Bool?
    let body: String?
    let assets: [GitHubAsset]?
    let html_url: String?

    var versionTag: String { tag_name }
}

private struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int?
    let content_type: String?
}
