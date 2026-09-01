import Foundation

/// Per-type "how do I rebuild this from local SQLite?" + "how do I merge
/// a remote into local SQLite?" hooks. Decouples SyncCore from concrete
/// stores (ChatStore / SkillStore / ProviderConfigStore / ...).
///
/// Each store registers its hooks at app launch. SyncCore looks them up
/// by recordType when building the outbound batch and when applying
/// inbound records.
///
/// Why two separate hook surfaces (build vs merge) rather than one
/// "Syncable model"-style protocol: the build path needs to load from
/// SQLite (recordType + id → SyncedX), while the merge path takes a
/// PortableRecord and integrates it with conflict resolution. Stores
/// already have those code paths in different places (mergeRemoteX
/// methods etc.) — letting them register two separate closures is the
/// least-invasive way to plug v2 in.
@MainActor
final class SyncCoreHydrators {
    static let shared = SyncCoreHydrators()
    private init() {}

    /// "Given recordType + id, return a PortableRecord ready to push (or
    /// nil if the local row no longer exists)." Called on the SyncCore
    /// actor; implementations are free to await actor hops internally.
    typealias Builder = (_ id: String) async -> PortableRecord?

    /// "Given a remote PortableRecord, merge it into local SQLite using
    /// this type's conflict resolution." Should be a no-op when the
    /// record cannot be applied (e.g. unknown schema version was already
    /// filtered upstream by SyncCore).
    typealias Merger = (_ record: PortableRecord) async -> Void

    /// "Given a record id, propagate its remote deletion locally — but
    /// honour soft-delete / tombstone rules per §3.3." Optional; if not
    /// registered, SyncCore falls back to a hard delete via direct SQL.
    typealias DeletionApplier = (_ id: String) async -> Void

    /// [T-icloud-thermal-batch-build] Batch builder: given an array of ids
    /// for the same recordType, return a map of id → PortableRecord.
    /// Implementations should use a single SQL query (WHERE id IN (...))
    /// instead of N separate queries. Ids missing from the result map are
    /// treated as "local row gone" by the caller (same semantics as
    /// buildPortable returning nil). Reduces O(n) DB round-trips to O(1)
    /// per batch — the primary CPU bottleneck during iCloud sync.
    typealias BatchBuilder = (_ ids: [String]) async -> [String: PortableRecord]

    private var builders: [String: Builder] = [:]
    private var mergers: [String: Merger] = [:]
    private var deleters: [String: DeletionApplier] = [:]
    private var batchBuilders: [String: BatchBuilder] = [:]

    func register(
        recordType: String,
        builder: Builder?,
        merger: Merger?,
        deletionApplier: DeletionApplier? = nil
    ) {
        if let b = builder { builders[recordType] = b }
        if let m = merger { mergers[recordType] = m }
        if let d = deletionApplier { deleters[recordType] = d }
    }

    /// [T-icloud-thermal-batch-build] Register a batch builder for a
    /// recordType. When set, SyncCore.sendNow() groups dirty rows by type
    /// and calls this instead of per-record buildPortable(). Falls back to
    /// the single-record Builder for types without a batch builder.
    func registerBatchBuilder(recordType: String, batchBuilder: @escaping BatchBuilder) {
        batchBuilders[recordType] = batchBuilder
    }

    /// True when this recordType has a batch builder registered.
    func hasBatchBuilder(recordType: String) -> Bool {
        batchBuilders[recordType] != nil
    }

    func buildPortable(recordType: String, id: String) async -> PortableRecord? {
        guard let b = builders[recordType] else {
            // No builder yet — type is registered for read-only consumption.
            return nil
        }
        return await b(id)
    }

    /// [T-icloud-thermal-batch-build] Batch-build PortableRecords for a set
    /// of ids of the same recordType. Uses the registered BatchBuilder
    /// (single SQL query) when available; otherwise falls back to calling
    /// buildPortable() per id. Returns a map of [id: PortableRecord]; ids
    /// not in the map have no local row (same semantics as nil return).
    func buildPortableBatch(recordType: String, ids: [String]) async -> [String: PortableRecord] {
        if let bb = batchBuilders[recordType] {
            return await bb(ids)
        }
        // Fallback: per-record build (same behavior as before this optimization)
        var result: [String: PortableRecord] = [:]
        for id in ids {
            if let p = await buildPortable(recordType: recordType, id: id) {
                result[id] = p
            }
        }
        return result
    }

    /// True when this recordType has a builder closure registered. Used by
    /// SyncCore to differentiate "local row gone (clear dirty safe)" from
    /// "no builder registered yet (must NOT clear dirty)" — see audit C3.
    func hasBuilder(recordType: String) -> Bool {
        builders[recordType] != nil
    }

    func mergeRemote(_ record: PortableRecord) async {
        // Honour the same per-category upload toggle on the inbound side.
        // If the user has turned off, say, Memory Files in iCloud Sync
        // settings, this device should neither push local writes nor
        // accept remote ones — otherwise toggling off only "saves your
        // own bandwidth" while peer writes still silently land on disk.
        // SyncDeviceV2 / unknown record types pass through (same rule as
        // UploadPolicy.allowsRecordType).
        guard UploadPolicy.allowsRecordType(record.id.type) else {
            return
        }
        guard let m = mergers[record.id.type] else { return }
        await m(record)
    }

    func applyRemoteDeletion(_ id: SyncRecordID) async {
        // Same gate as mergeRemote — a disabled category should not have
        // its local rows wiped by a remote tombstone either.
        guard UploadPolicy.allowsRecordType(id.type) else { return }
        if let d = deleters[id.type] {
            await d(id.id)
            return
        }
        // No-op fallback. Stores that don't register a deletion applier
        // get default-keep behavior (the record stays locally), which is
        // safe but not necessarily what the type wants. SyncCore logs the
        // gap so the omission is visible at runtime.
    }

    var registeredRecordTypes: [String] {
        Array(Set(builders.keys).union(mergers.keys).union(deleters.keys)).sorted()
    }
}
