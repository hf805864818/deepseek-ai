import AppIntents
import Foundation

/// [T-deep-mode-phase-e] Runs a stored scheduled task immediately, on demand.
///
/// Exposed to Shortcuts so users can build a `Time of Day` / `Date` automation
/// that triggers a saved scheduled task without reopening the app each time.
/// This is the execution half of the "Shortcuts 自动化" trigger channel: the
/// user points an automation at this intent and picks the task to run.
@available(iOS 16.0, *)
struct RunScheduledTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scheduled Task"
    static var description = IntentDescription("Runs one of your saved Minis scheduled tasks immediately.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Run scheduled task \(\.$task)")
    }

    /// The scheduled task to run. Backed by AppEntity lookup so Shortcuts shows
    /// a picker of the user's saved tasks.
    @Parameter(title: "Scheduled Task")
    var task: ScheduledTaskEntity?

    /// Free-form override: when no entity is chosen, treat this as the taskId.
    @Parameter(title: "Task ID",
               description: "The id of the scheduled task to run (used when 'Scheduled Task' is empty).",
               requestValueDialog: "Enter the task id")
    var taskIdOverride: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RunScheduledTaskResult> & ProvidesDialog {
        let id = task?.id ?? taskIdOverride ?? ""
        guard !id.isEmpty else {
            throw ScheduledTaskIntentError.noSelection
        }
        let store = ScheduledTaskStore()
        guard let item = store.task(id) else {
            throw ScheduledTaskIntentError.notFound
        }

        // Fire-and-forget the run; the result is reported via the return value.
        _ = await ScheduledTaskPromptLauncher.launch(item)

        let result = RunScheduledTaskResult(
            taskId: item.id,
            label: item.label,
            prompt: item.prompt,
            status: "Running",
            triggeredAt: Date().timeIntervalSince1970
        )
        return .result(value: result, dialog: "\(item.label) started in a new chat.")
    }
}

/// User-facing error surfaced by the intent (works on iOS 16+; unlike
/// IntentFailure.customMessage which requires iOS 17+).
private enum ScheduledTaskIntentError: String, LocalizedError {
    case noSelection
    case notFound

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "No scheduled task selected. Pick a task or supply a Task ID."
        case .notFound:
            return "That scheduled task could not be found. It may have been deleted."
        }
    }
}

/// The scheduled task as a pickable Shortcuts entity.
@available(iOS 16.0, *)
struct ScheduledTaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scheduled Task"
    static let defaultQuery = ScheduledTaskEntityQuery()

    var id: String
    var label: String
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(label)")
    }
    static func from(_ item: ScheduledTaskItem) -> ScheduledTaskEntity {
        .init(id: item.id, label: item.label)
    }
}

@available(iOS 16.0, *)
struct ScheduledTaskEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ScheduledTaskEntity] {
        let store = ScheduledTaskStore()
        let items = store.tasks
        return identifiers.compactMap { id in
            items.first { $0.id == id }.map { .from($0) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [ScheduledTaskEntity] {
        ScheduledTaskStore().tasks.map { .from($0) }
    }
}

/// Result payload returned by RunScheduledTaskIntent.
/// `Codable` + `Sendable` is all that `ReturnsValue<RunScheduledTaskResult>` requires
/// (there is no public `AppIntentResult` base protocol to conform to).
struct RunScheduledTaskResult: Codable, Sendable {
    let taskId: String
    let label: String
    let prompt: String
    let status: String
    let triggeredAt: Double
}