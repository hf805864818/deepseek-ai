import Foundation
import os.log

private let logger = AppLogger(category: "AppSettingsSync")

/// Helper that bridges user-facing UserDefaults settings into cross-device
/// sync. Collects a curated set of preferences into a JSON blob and applies
/// inbound settings locally with last-write-wins (LWW) by `updatedAt`.
///
/// Two transport paths are supported:
///   1. **iCloud sync** (if enabled): pushes settings as a single
///      `AppSettingsV2` PortableRecord via SyncCore.
///   2. **Google Drive backup**: settings JSON is included in the backup
///      ZIP as `settings/settings.json` and applied on restore.
///
/// Both paths share the same `collectSettings()` / `applySettings()` core,
/// so the transport is transparent to the data layer.
///
/// Device-specific settings (Google Drive auth, iCloud toggle, rootfs state,
/// logging, auth tokens) are intentionally excluded — each device owns those.
@MainActor
enum AppSettingsSync {

    // MARK: - Syncable keys

    /// UserDefaults keys that participate in cross-device sync.
    /// Each entry maps a sync wire-name to its UserDefaults key and type.
    private struct SyncableKey {
        let wireName: String
        let defaultsKey: String
        let type: KeyType

        enum KeyType { case string, bool, int, double }
    }

    private static let syncableKeys: [SyncableKey] = [
        SyncableKey(wireName: "appearanceMode",              defaultsKey: "appearanceMode",              type: .int),
        SyncableKey(wireName: "autoGroupingEnabled",          defaultsKey: "autoGroupingEnabled",         type: .bool),
        SyncableKey(wireName: "memoryGlobalEnabled",          defaultsKey: "memory.global.enabled",      type: .bool),
        SyncableKey(wireName: "backgroundNotificationsEnabled", defaultsKey: "backgroundNotificationsEnabled", type: .bool),
        SyncableKey(wireName: "fontChatInput",               defaultsKey: "font.chatInput",              type: .string),
        SyncableKey(wireName: "fontMessageBase",             defaultsKey: "font.messageBase",            type: .string),
        SyncableKey(wireName: "fontAppBase",                 defaultsKey: "font.appBase",                type: .string),
    ]

    /// UserDefaults key tracking the last time local settings were changed.
    /// Used as the LWW clock for settings — shared by both iCloud and
    /// Google Drive paths.
    private static let localUpdatedAtKey = "appSettings.localUpdatedAt"

    /// Snapshot of the last-collected settings JSON. Compared on each
    /// `checkAndMarkDirty()` call to detect whether any syncable setting
    /// changed since the last push.
    private static let lastPushedSnapshotKey = "appSettings.lastPushedSnapshot"

    // MARK: - Collect (local → JSON)

    /// Reads all syncable settings from UserDefaults and returns them as a
    /// JSON string. The same format is used for both iCloud and Google Drive.
    static func collectSettings() -> String {
        var dict: [String: String] = [:]
        for key in syncableKeys {
            switch key.type {
            case .string:
                dict[key.wireName] = UserDefaults.standard.string(forKey: key.defaultsKey) ?? ""
            case .bool:
                dict[key.wireName] = UserDefaults.standard.bool(forKey: key.defaultsKey) ? "true" : "false"
            case .int:
                dict[key.wireName] = String(UserDefaults.standard.integer(forKey: key.defaultsKey))
            case .double:
                dict[key.wireName] = String(UserDefaults.standard.double(forKey: key.defaultsKey))
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to serialize settings JSON")
            return "{}"
        }
        return json
    }

    /// Returns the local `updatedAt` timestamp for LWW comparison.
    static func localUpdatedAt() -> Date {
        let ts = UserDefaults.standard.double(forKey: localUpdatedAtKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    // MARK: - Apply (JSON → local)

    /// Applies a remote settings JSON blob to local UserDefaults. Uses LWW:
    /// only applies if the remote `updatedAt` is strictly newer than the
    /// local `localUpdatedAt`. After applying, stamps the local updatedAt
    /// to the remote value so future remote changes are compared correctly.
    ///
    /// This method is called from both iCloud sync (mergeAppSettings) and
    /// Google Drive restore (mergeBackupNewFormat).
    static func applySettings(_ json: String, remoteUpdatedAt: Date) {
        // LWW guard — skip if local is newer or equal
        let local = localUpdatedAt()
        guard remoteUpdatedAt > local else {
            logger.info("applySettings SKIP (local newer): local=\(local) remote=\(remoteUpdatedAt)")
            return
        }

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            logger.error("Failed to parse settings JSON")
            return
        }

        for key in syncableKeys {
            guard let value = dict[key.wireName] else { continue }
            switch key.type {
            case .string:
                UserDefaults.standard.set(value, forKey: key.defaultsKey)
            case .bool:
                UserDefaults.standard.set(value == "true", forKey: key.defaultsKey)
            case .int:
                UserDefaults.standard.set(Int(value) ?? 0, forKey: key.defaultsKey)
            case .double:
                UserDefaults.standard.set(Double(value) ?? 0, forKey: key.defaultsKey)
            }
        }

        // Stamp local updatedAt to the remote value
        UserDefaults.standard.set(remoteUpdatedAt.timeIntervalSince1970, forKey: localUpdatedAtKey)
        // Update the snapshot so the next checkAndMarkDirty doesn't re-mark
        UserDefaults.standard.set(json, forKey: lastPushedSnapshotKey)
        logger.info("Applied remote settings (updatedAt=\(remoteUpdatedAt))")
    }

    // MARK: - Google Drive backup support

    /// Builds a complete settings JSON payload for Google Drive backup,
    /// including the `updatedAt` timestamp wrapper. Returns nil if no
    /// local settings have ever been changed.
    static func buildBackupPayload() -> Data? {
        let updatedAt = localUpdatedAt()
        guard updatedAt > .distantPast else {
            logger.info("buildBackupPayload: no local settings change — skipping")
            return nil
        }

        let settingsJson = collectSettings()
        let payload: [String: Any] = [
            "updatedAt": updatedAt.timeIntervalSince1970,
            "settings": (try? JSONSerialization.jsonObject(with: settingsJson.data(using: .utf8) ?? Data())) ?? [:]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            logger.error("Failed to serialize settings backup payload")
            return nil
        }
        return data
    }

    /// Applies settings from a Google Drive backup JSON payload. Extracts
    /// the `updatedAt` and `settings` fields and delegates to
    /// `applySettings(_:remoteUpdatedAt:)` with LWW.
    static func applyBackupPayload(_ data: Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedAtTs = payload["updatedAt"] as? TimeInterval,
              let settingsDict = payload["settings"] as? [String: Any] else {
            logger.error("Failed to parse settings backup payload")
            return
        }

        // Re-serialize the settings dict to a string for applySettings
        guard let settingsData = try? JSONSerialization.data(withJSONObject: settingsDict, options: [.sortedKeys]),
              let settingsJson = String(data: settingsData, encoding: .utf8) else {
            logger.error("Failed to re-serialize settings from backup payload")
            return
        }

        let remoteUpdatedAt = Date(timeIntervalSince1970: updatedAtTs)
        applySettings(settingsJson, remoteUpdatedAt: remoteUpdatedAt)
    }

    // MARK: - Mark dirty (iCloud path)

    /// Stamps the local `updatedAt` to now and marks the AppSettingsV2
    /// record dirty so it will be pushed on the next iCloud sync cycle.
    /// Only effective if iCloud sync is enabled; if not, the stamp still
    /// updates the LWW clock so Google Drive backup includes the change.
    static func markDirty() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: localUpdatedAtKey)
        UserDefaults.standard.set(collectSettings(), forKey: lastPushedSnapshotKey)

        // Only push to SyncCore if iCloud sync is enabled
        if UserDefaults.standard.bool(forKey: "cloudSync.v2.enabled") {
            Task {
                await SyncCore.shared.markDirty(
                    SyncedAppSettings(id: "app-settings",
                                      settingsJson: collectSettings(),
                                      updatedAt: now),
                    reason: .localUpsert
                )
            }
            logger.info("AppSettings marked dirty for iCloud (updatedAt=\(now))")
        } else {
            logger.info("AppSettings stamped for Google Drive backup (updatedAt=\(now))")
        }
    }

    /// Compares the current settings snapshot with the last-pushed one.
    /// If they differ, stamps the local updatedAt and marks the record dirty
    /// for the next sync cycle. Called periodically from SyncCore.sendNow —
    /// avoids the need to hook every individual UserDefaults write path.
    ///
    /// If iCloud is not enabled, this is a no-op (Google Drive captures
    /// the latest settings at backup time via `buildBackupPayload()`).
    static func checkAndMarkDirty() {
        guard UserDefaults.standard.bool(forKey: "cloudSync.v2.enabled") else { return }

        let current = collectSettings()
        let lastPushed = UserDefaults.standard.string(forKey: lastPushedSnapshotKey) ?? ""
        guard current != lastPushed else { return }
        // Settings changed since the last push — stamp and mark dirty
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: localUpdatedAtKey)
        UserDefaults.standard.set(current, forKey: lastPushedSnapshotKey)
        Task {
            await SyncCore.shared.markDirty(
                SyncedAppSettings(id: "app-settings",
                                  settingsJson: current,
                                  updatedAt: now),
                reason: .localUpsert
            )
        }
        logger.info("AppSettings change detected — marked dirty")
    }
}
