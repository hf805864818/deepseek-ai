import Foundation
import Security
import os.log

private let logger = AppLogger(category: "EnvProfileStore")

// MARK: - EnvProfile

/// An environment variable profile (a named set of env vars that can be
/// activated per-session). Profiles sit above global env vars in the
/// resolution order: profile vars override global vars with the same key.
struct EnvProfile: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var icon: String?       // SF Symbol name, e.g. "briefcase", "person"
    var color: String?      // theme color token (optional)
    var isDefault: Bool     // whether this is the default profile for new sessions
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String? = nil,
        color: String? = nil,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - EnvProfileVar

/// A single environment variable entry within a profile.
/// The value is stored in the Keychain under a profile-scoped key.
struct EnvProfileVar: Identifiable, Codable, Hashable {
    let id: String
    let profileId: String
    var key: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        profileId: String,
        key: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.key = key
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - EnvProfileStore

/// Manages env var profiles and their variables.
///
/// Storage layout:
///   Library/MinisChat/env-profiles.json   → list of profiles
///   Library/MinisChat/env-profile-vars.json  → list of all profile vars (flat)
///   Keychain → values, keyed by "profile:<profileId>:<varKey>"
///
/// Values live in the Keychain (same pattern as EnvVarStore but with a
/// "profile:" prefix) so they sync via iCloud Keychain and stay encrypted.
@MainActor
final class EnvProfileStore: ObservableObject {
    static let shared = EnvProfileStore()

    @Published private(set) var profiles: [EnvProfile] = []
    @Published private(set) var vars: [EnvProfileVar] = []

    private let profilesURL: URL
    private let varsURL: URL
    nonisolated private static let keychainService = "com.openminis.app.envvar"

    init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let baseURL = libraryURL.appendingPathComponent("MinisChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.profilesURL = baseURL.appendingPathComponent("env-profiles.json")
        self.varsURL = baseURL.appendingPathComponent("env-profile-vars.json")
        self.profiles = Self.loadProfiles(from: profilesURL)
        self.vars = Self.loadVars(from: varsURL)
    }

    // MARK: - Persistence

    private static func loadProfiles(from url: URL) -> [EnvProfile] {
        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([EnvProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    private static func loadVars(from url: URL) -> [EnvProfileVar] {
        guard let data = try? Data(contentsOf: url),
              let vars = try? JSONDecoder().decode([EnvProfileVar].self, from: data) else {
            return []
        }
        return vars
    }

    func reloadFromDisk() {
        profiles = Self.loadProfiles(from: profilesURL)
        vars = Self.loadVars(from: varsURL)
    }

    private func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesURL, options: .atomic)
        } catch {
            logger.error("Failed to save env profiles: \(error)")
        }
    }

    private func saveVars() {
        do {
            let data = try JSONEncoder().encode(vars)
            try data.write(to: varsURL, options: .atomic)
        } catch {
            logger.error("Failed to save env profile vars: \(error)")
        }
    }

    // MARK: - Keychain (profile-scoped values)

    /// Keychain account key for a profile-scoped var.
    nonisolated static func profileKeychainKey(profileId: String, key: String) -> String {
        "profile:\(profileId):\(key)"
    }

    @discardableResult
    nonisolated private static func saveValue(_ value: String, profileId: String, key: String) -> Bool {
        let accountKey = profileKeychainKey(profileId: profileId, key: key)
        let syncMatch: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountKey,
            kSecAttrSynchronizable as String: true,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemUpdate(syncMatch as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = syncMatch
            addQuery.merge(attrs) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(syncMatch as CFDictionary, attrs as CFDictionary)
            }
        }

        if status == errSecSuccess {
            return true
        }
        logger.error("Keychain save failed for profile \(profileId) key \(key): OSStatus \(status)")
        return false
    }

    /// Non-isolated read for use from sync engine (background thread).
    nonisolated static func loadValueSync(profileId: String, key: String) -> String? {
        loadValue(profileId: profileId, key: key)
    }

    nonisolated private static func loadValue(profileId: String, key: String) -> String? {
        let accountKey = profileKeychainKey(profileId: profileId, key: key)
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountKey,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(syncQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return String(data: data, encoding: .utf8) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func deleteValue(profileId: String, key: String) {
        let accountKey = profileKeychainKey(profileId: profileId, key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
        var syncQuery = query
        syncQuery[kSecAttrSynchronizable as String] = true
        SecItemDelete(syncQuery as CFDictionary)
    }

    // MARK: - Value Sanitization (reuse EnvVarStore logic)

    private static func sanitizeValue(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            (scalar.value >= 0x20 && scalar.value <= 0x7E) || scalar.value == 0x09
        })
    }

    // MARK: - Public API — Profiles

    var defaultProfile: EnvProfile? {
        profiles.first(where: { $0.isDefault })
    }

    func profile(id: String) -> EnvProfile? {
        profiles.first(where: { $0.id == id })
    }

    func varItem(id: String) -> EnvProfileVar? {
        vars.first(where: { $0.id == id })
    }

    func addProfile(name: String, icon: String? = nil, color: String? = nil, isDefault: Bool = false) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // If this is the new default, clear the old default
        if isDefault {
            for idx in profiles.indices {
                profiles[idx].isDefault = false
            }
        }

        let profile = EnvProfile(name: trimmedName, icon: icon, color: color, isDefault: isDefault)
        profiles.append(profile)
        saveProfiles()
        markProfileDirty(profileId: profile.id)
        logger.info("Added env profile: \(trimmedName)")
    }

    func updateProfile(id: String, name: String, icon: String?, color: String?, isDefault: Bool) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // If this is becoming the default, clear other defaults
        if isDefault && !profiles[idx].isDefault {
            for i in profiles.indices where i != idx {
                profiles[i].isDefault = false
            }
        }

        profiles[idx].name = trimmedName
        profiles[idx].icon = icon
        profiles[idx].color = color
        profiles[idx].isDefault = isDefault
        profiles[idx].updatedAt = Date()
        saveProfiles()
        markProfileDirty(profileId: id)
        logger.info("Updated env profile: \(trimmedName)")
    }

    func deleteProfile(id: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profileId = profiles[idx].id
        let name = profiles[idx].name

        // Delete all vars in this profile
        let varsToDelete = vars.filter { $0.profileId == profileId }
        for v in varsToDelete {
            Self.deleteValue(profileId: profileId, key: v.key)
            markProfileVarDirty(varId: v.id, operation: "delete")
        }
        vars.removeAll { $0.profileId == profileId }

        profiles.remove(at: idx)
        saveProfiles()
        saveVars()
        markProfileDirty(profileId: id, operation: "delete")
        logger.info("Deleted env profile: \(name) (id: \(id.prefix(8)))")
    }

    // MARK: - Public API — Profile Vars

    func vars(for profileId: String) -> [EnvProfileVar] {
        vars.filter { $0.profileId == profileId }.sorted { $0.key < $1.key }
    }

    func value(for profileId: String, key: String) -> String? {
        Self.loadValue(profileId: profileId, key: key)
    }

    func addVar(to profileId: String, key: String, value: String, note: String = "") {
        guard profiles.contains(where: { $0.id == profileId }) else { return }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedKey.isEmpty, EnvVarStore.isValidKey(trimmedKey) else { return }

        // Don't allow duplicate keys within the same profile
        guard !vars.contains(where: { $0.profileId == profileId && $0.key == trimmedKey }) else {
            logger.warning("Duplicate env var key in profile \(profileId): \(trimmedKey)")
            return
        }

        let cleanValue = Self.sanitizeValue(value)
        guard Self.saveValue(cleanValue, profileId: profileId, key: trimmedKey) else {
            logger.error("Add profile var aborted — Keychain write failed for \(trimmedKey)")
            return
        }

        let entry = EnvProfileVar(profileId: profileId, key: trimmedKey, note: note)
        vars.append(entry)
        saveVars()
        markProfileVarDirty(varId: entry.id)

        // Bump profile updatedAt
        if let idx = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[idx].updatedAt = Date()
            saveProfiles()
            markProfileDirty(profileId: profileId)
        }

        logger.info("Added env var to profile \(profileId.prefix(8)): \(trimmedKey)")
    }

    func updateVar(id: String, key: String, value: String, note: String? = nil) {
        guard let idx = vars.firstIndex(where: { $0.id == id }) else { return }

        let profileId = vars[idx].profileId
        let oldKey = vars[idx].key
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedKey.isEmpty, EnvVarStore.isValidKey(trimmedKey) else { return }

        // If key changed, delete old keychain entry and check for duplicates
        if oldKey != trimmedKey {
            guard !vars.contains(where: { $0.profileId == profileId && $0.key == trimmedKey && $0.id != id }) else {
                logger.warning("Cannot rename profile var to duplicate key: \(trimmedKey)")
                return
            }
            Self.deleteValue(profileId: profileId, key: oldKey)
        }

        let cleanValue = Self.sanitizeValue(value)
        guard Self.saveValue(cleanValue, profileId: profileId, key: trimmedKey) else {
            logger.error("Update profile var aborted — Keychain write failed for \(trimmedKey)")
            return
        }

        vars[idx].key = trimmedKey
        if let note { vars[idx].note = note }
        vars[idx].updatedAt = Date()
        saveVars()
        markProfileVarDirty(varId: id)

        // Bump profile updatedAt
        if let pIdx = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[pIdx].updatedAt = Date()
            saveProfiles()
            markProfileDirty(profileId: profileId)
        }

        logger.info("Updated env var in profile \(profileId.prefix(8)): \(trimmedKey)")
    }

    func deleteVar(id: String) {
        guard let idx = vars.firstIndex(where: { $0.id == id }) else { return }
        let profileId = vars[idx].profileId
        let key = vars[idx].key
        Self.deleteValue(profileId: profileId, key: key)
        vars.remove(at: idx)
        saveVars()
        markProfileVarDirty(varId: id, operation: "delete")

        // Bump profile updatedAt
        if let pIdx = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[pIdx].updatedAt = Date()
            saveProfiles()
            markProfileDirty(profileId: profileId)
        }

        logger.info("Deleted env var from profile \(profileId.prefix(8)): \(key)")
    }

    // MARK: - Resolved env (global + profile merged)

    /// Returns the full resolved environment dictionary for a given profile.
    /// Profile vars override global vars with the same key.
    nonisolated func resolvedEnv(forProfile profileId: String?) -> [String: String] {
        var result = EnvVarStore.shared.allAsDict()
        guard let profileId else { return result }

        // Read profile vars from disk (nonisolated path)
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let varsURL = libraryURL.appendingPathComponent("MinisChat/env-profile-vars.json")
        guard let data = try? Data(contentsOf: varsURL),
              let allVars = try? JSONDecoder().decode([EnvProfileVar].self, from: data) else {
            return result
        }

        let profileVars = allVars.filter { $0.profileId == profileId }
        for v in profileVars {
            if let val = Self.loadValue(profileId: profileId, key: v.key) {
                result[v.key] = val
            }
        }
        return result
    }

    // MARK: - Sync dirty tracking

    fileprivate func markProfileDirty(profileId: String, operation: String = "upsert") {
        Task { await ChatStore.shared.markDirty(
            recordType: "EnvProfile",
            recordId: profileId,
            operation: operation
        ) }
    }

    fileprivate func markProfileVarDirty(varId: String, operation: String = "upsert") {
        Task { await ChatStore.shared.markDirty(
            recordType: "EnvProfileVar",
            recordId: varId,
            operation: operation
        ) }
    }

    func markAllDirty() {
        for p in profiles {
            markProfileDirty(profileId: p.id)
        }
        for v in vars {
            markProfileVarDirty(varId: v.id)
        }
    }

    // MARK: - Sync inbound

    /// Apply an inbound EnvProfile record (from iCloud sync).
    func applyRemoteProfile(
        id: String, name: String, icon: String?, color: String?,
        isDefault: Bool, createdAt: Date, updatedAt: Date
    ) {
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            let existing = profiles[idx]
            // Accept inbound update; last-writer-wins by updatedAt ordering
            // from the cloud stream.
            profiles[idx].name = name
            profiles[idx].icon = icon
            profiles[idx].color = color
            if isDefault && !existing.isDefault {
                // Clear other defaults when this one becomes default
                for i in profiles.indices where i != idx {
                    profiles[i].isDefault = false
                }
            } else if !isDefault && existing.isDefault {
                profiles[idx].isDefault = false
            }
            if existing.createdAt > createdAt { profiles[idx].createdAt = createdAt }
            profiles[idx].updatedAt = updatedAt
            saveProfiles()
            logger.info("[EnvProfileStore] applyRemoteProfile UPDATE id=\(id.prefix(8)) name=\(name)")
        } else {
            let profile = EnvProfile(
                id: id, name: name, icon: icon, color: color,
                isDefault: isDefault, createdAt: createdAt, updatedAt: updatedAt
            )
            profiles.append(profile)
            saveProfiles()
            logger.info("[EnvProfileStore] applyRemoteProfile INSERT id=\(id.prefix(8)) name=\(name)")
        }
    }

    func applyRemoteProfileDeletion(id: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profileId = profiles[idx].id
        // Delete all vars in this profile
        let varsToDelete = vars.filter { $0.profileId == profileId }
        for v in varsToDelete {
            Self.deleteValue(profileId: profileId, key: v.key)
        }
        vars.removeAll { $0.profileId == profileId }
        profiles.remove(at: idx)
        saveProfiles()
        saveVars()
        logger.info("[EnvProfileStore] applyRemoteProfileDeletion id=\(id.prefix(8))")
    }

    /// Apply an inbound EnvProfileVar record (from iCloud sync).
    func applyRemoteProfileVar(
        id: String, profileId: String, key: String, value: String,
        note: String, createdAt: Date, updatedAt: Date
    ) {
        // Silently skip if the profile doesn't exist locally (it may
        // arrive before the profile record in the sync stream).
        guard profiles.contains(where: { $0.id == profileId }) else {
            logger.warning("[EnvProfileStore] applyRemoteProfileVar: profile \(profileId.prefix(8)) not found, skipping var \(key)")
            return
        }

        if let idx = vars.firstIndex(where: { $0.id == id }) {
            let existing = vars[idx]
            let keyChanged = existing.key != key
            vars[idx].key = key
            vars[idx].note = note
            if existing.createdAt > createdAt { vars[idx].createdAt = createdAt }
            vars[idx].updatedAt = updatedAt
            if !value.isEmpty {
                if keyChanged {
                    Self.deleteValue(profileId: profileId, key: existing.key)
                }
                Self.saveValue(value, profileId: profileId, key: key)
            } else if keyChanged {
                if let oldVal = Self.loadValue(profileId: profileId, key: existing.key) {
                    Self.saveValue(oldVal, profileId: profileId, key: key)
                    Self.deleteValue(profileId: profileId, key: existing.key)
                }
            }
            saveVars()
            logger.info("[EnvProfileStore] applyRemoteProfileVar UPDATE id=\(id.prefix(8)) key=\(key)")
        } else {
            let entry = EnvProfileVar(
                id: id, profileId: profileId, key: key, note: note,
                createdAt: createdAt, updatedAt: updatedAt
            )
            vars.append(entry)
            if !value.isEmpty {
                Self.saveValue(value, profileId: profileId, key: key)
            }
            saveVars()
            logger.info("[EnvProfileStore] applyRemoteProfileVar INSERT id=\(id.prefix(8)) key=\(key)")
        }
    }

    func applyRemoteProfileVarDeletion(id: String) {
        guard let idx = vars.firstIndex(where: { $0.id == id }) else { return }
        let profileId = vars[idx].profileId
        let key = vars[idx].key
        Self.deleteValue(profileId: profileId, key: key)
        vars.remove(at: idx)
        saveVars()
        logger.info("[EnvProfileStore] applyRemoteProfileVarDeletion id=\(id.prefix(8)) key=\(key)")
    }
}
