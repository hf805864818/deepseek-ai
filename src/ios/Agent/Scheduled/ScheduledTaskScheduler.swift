import Foundation
import UIKit
import UserNotifications

/// [T-deep-mode-phase-e] iOS scheduling proxy for scheduled tasks.
///
/// iOS has no system-level cron, so a scheduled task here is surfaced as a
/// local notification at its next wall-clock trigger (daily / weekdays /
/// custom repeat). Tapping the notification opens the app, where the task
/// can be run (or the user can rely on the app's open-time catch-up pass to
/// fire anything due while it was suspended). This mirrors Android's AlarmManager
/// semantics as closely as the platform allows: notify at the trigger time,
/// and on next app open, run any task whose trigger already passed and record
/// the result. It is deliberately "best effort" and never silently drops a
/// task — a missed fire is caught on the next open.
///
/// Total-switch boundary: this scheduler and the store it drives are part of
/// the "已建任务管理"常驻 capability. They stay available (and keep firing)
/// even when the deep-mode switch is off, so turning the switch off never
/// strands a background task the user cannot find. Only the `schedule_task`
/// *tool* (creation) is gated by the master switch.
@MainActor
final class ScheduledTaskScheduler: ObservableObject {
    static let shared = ScheduledTaskScheduler()

    private(set) var store = ScheduledTaskStore()

    /// Notification identifier prefix; task-specific ids are prefixed with it.
    static let notificationIdPrefix = "minis.scheduled-task"

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rescheduleAllFromNotification),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        store.reload()
        Task { await rescheduleAll() }
    }

    @objc private func rescheduleAllFromNotification() {
        Task { await rescheduleAll(); await runDueTasks() }
    }

    /// (Re)arm local notifications for every enabled task, cancelling any
    /// previously scheduled ones so the set always mirrors the store.
    func rescheduleAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // whole queue is ours
        for task in store.tasks where task.enabled {
            scheduleOne(task)
        }
    }

    private func scheduleOne(_ task: ScheduledTaskItem) {
        guard task.enabled, let next = ScheduledTaskItem.nextTriggerDate(task, from: Date()) else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = AppLocalized("Scheduled Task")
        content.body = "\(task.label) — \(task.prompt.prefix(80))"
        content.sound = .default
        content.userInfo = ["taskId": task.id]
        content.categoryIdentifier = "SCHEDULED_TASK"

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(Self.notificationIdPrefix).\(task.id)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - CRUD (kept available regardless of master switch)

    @discardableResult
    func upsert(_ task: ScheduledTaskItem) -> ScheduledTaskItem {
        let saved = store.upsert(task)
        cancelOne(saved)
        scheduleOne(saved)
        return saved
    }

    func delete(_ id: String) {
        store.delete(id)
        cancelOneID(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        store.setEnabled(id, enabled)
        let tasks = store.tasks.filter { $0.id == id }
        cancelOneID(id)
        if let task = tasks.first, enabled { scheduleOne(task) }
    }

    private func cancelOne(_ task: ScheduledTaskItem) { cancelOneID(task.id) }

    private func cancelOneID(_ id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(Self.notificationIdPrefix).\(id)"])
    }

    // MARK: - Catch-up on open

    /// Runs any task whose next trigger has already passed while the app was
    /// away, recording the run. Keeps 'once' tasks from firing multiple times.
    func runDueTasks() async {
        let now = Date()
        var due: [ScheduledTaskItem] = []
        for task in store.tasks where task.enabled {
            guard let next = ScheduledTaskItem.nextTriggerDate(task, from: now) else { continue }
            // A trigger in the past (immediately before now) qualifies as due,
            // but only if it lies within the repeat window for repeating tasks.
            if now.timeIntervalSince(next) >= 0 {
                due.append(task)
            }
        }
        guard !due.isEmpty else { return }
        for task in due {
            fire(task)
        }
    }

    /// Records a run and optionally launches the prompt in a fresh chat.
    /// Async fire-and-forget is left to the caller; here we just mark history.
    func fire(_ task: ScheduledTaskItem) {
        guard var updated = store.task(task.id) else { return }
        updated.lastFiredAt = Date().timeIntervalSince1970
        updated.lastResultPreview = "Triggered at \(Date().formatted(date: .abbreviated, time: .shortened)) — opened task in a fresh chat."
        store.upsert(updated)
        // Launch the prompt through SendPromptIntent so the agent actually runs it.
        Task { @MainActor in
            await ScheduledTaskPromptLauncher.launch(task)
        }
    }
}

/// Launches a scheduled task's prompt into a fresh chat via the existing
/// SendPromptIntent machinery, so the run reuses the full agent pipeline.
@MainActor
enum ScheduledTaskPromptLauncher {
    static func launch(_ task: ScheduledTaskItem) async {
        var intent = SendPromptIntent()
        intent.prompt = task.prompt
        // Create a fresh session. Fire-and-forget: we don't wait for result.
        _ = try? await intent.perform()
    }
}