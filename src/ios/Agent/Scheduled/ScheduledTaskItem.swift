import Foundation

/// [T-deep-mode-phase-e] A user-defined scheduled task (iOS).
///
/// iOS counterpart of Android's `ScheduledTask`. Because iOS cannot reliably run
/// a live agent loop at an exact wall-clock time in the background, a scheduled
/// task here persists the intent (label / prompt / time / repeat) and schedules a
/// local notification at the next trigger. The user can also surface it through
/// Shortcuts automation via `RunScheduledTaskIntent`.
///
/// Persistence: UserDefaults, mirrored to the Android schema shape (repeat mode
/// + HH:MM time) so the semantics stay consistent across platforms.
struct ScheduledTaskItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var label: String
    var prompt: String
    var hour: Int            // 0-23
    var minute: Int          // 0-59
    var repeatMode: String   // once | daily | weekdays | custom
    var customDays: [Int]    // Calendar.dayOfWeek values when repeatMode == custom
    var enabled: Bool = true
    var createdAt: Double = Date().timeIntervalSince1970
    var lastFiredAt: Double?
    var lastResultPreview: String?
    var lastResultSessionId: String?
}

/// [T-deep-mode-phase-e] UserDefaults-backed store for scheduled tasks.
@MainActor
final class ScheduledTaskStore: ObservableObject {
    @Published private(set) var tasks: [ScheduledTaskItem] = []

    private let key = "minis.scheduledTasks.items.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: key) else { tasks = []; return }
        tasks = (try? JSONDecoder().decode([ScheduledTaskItem].self, from: data)) ?? []
    }

    func task(_ id: String) -> ScheduledTaskItem? { tasks.first { $0.id == id } }

    @discardableResult
    func upsert(_ task: ScheduledTaskItem) -> ScheduledTaskItem {
        var list = tasks.filter { $0.id != task.id }
        list.append(task)
        tasks = list
        persist()
        return task
    }

    func delete(_ id: String) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].enabled = enabled
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: key)
        }
    }

    /// Next wall-clock trigger ms (local time), mirroring Android semantics for
    /// DISPLAY purposes only (not for exact background timing).
    func nextTriggerDate(_ t: ScheduledTaskItem, from now: Date = Date()) -> Date? {
        guard t.enabled else { return nil }
        return ScheduledTaskItem.nextTriggerDate(t, from: now)
    }
}

extension ScheduledTaskItem {
    static func nextTriggerDate(_ t: ScheduledTaskItem, from now: Date) -> Date? {
        var cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = t.hour
        comps.minute = t.minute
        comps.second = 0
        var candidate = cal.date(from: comps)!
        if candidate < now { cal.date(byAdding: .day, value: 1, to: candidate).map { candidate = $0 } }

        // Advance to a valid day for weekdays/custom repeats.
        var guardCount = 8
        while guardCount > 0 {
            let weekday = cal.component(.weekday, from: candidate)
            let allow = whenAllowed(t, weekday)
            if allow { break }
            candidate = cal.date(byAdding: .day, value: 1, to: candidate)!
            cal = Calendar.current
            guardCount -= 1
        }
        if guardCount <= 0 { return nil }
        return candidate
    }

    private static func whenAllowed(_ t: ScheduledTaskItem, _ weekday: Int) -> Bool {
        switch t.repeatMode {
        case "weekdays": return weekday != 1 && weekday != 7   // Sun=1, Sat=7
        case "custom": return t.customDays.contains(weekday)
        default: return true                                   // once + daily
        }
    }
}