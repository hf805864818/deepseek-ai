import SwiftUI

/// [T-deep-mode-phase-e] List + manage scheduled tasks (iOS).
///
/// Entry point from Settings → Agent Runtime → Scheduled Tasks. Mirrors the
/// Android `ui/scheduled/ScheduledTasksScreen`: list rows with enable/disable,
/// tap to edit, swipe/keyboard delete, and a detail/run-records view. This is
/// the "已建任务管理"常驻 surface — it stays reachable regardless of the
/// deep-mode master switch so a background task is never orphaned.
struct ScheduledTasksSettingsView: View {
    @StateObject private var scheduler = ScheduledTaskScheduler.shared
    @State private var showingEditor = false
    @State private var editingTask: ScheduledTaskItem?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if scheduler.store.tasks.isEmpty {
                    ContentUnavailableView(
                        "No Scheduled Tasks",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Ask the AI in deep mode to set a repeating task, e.g. \"每天 9 点生成日报\". Tasks appear here and run automatically.")
                    )
                } else {
                    ForEach(scheduler.store.tasks) { task in
                        ScheduledTaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTask = task; showingEditor = true }
                        #if os(iOS)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    scheduler.delete(task.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        #endif
                    }
                }
            }
            .navigationTitle("Scheduled Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingTask = nil
                        showingEditor = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                ScheduledTaskEditorView(
                    task: editingTask,
                    onSave: { updated in
                        let withID = editingTask.map { task in
                            ScheduledTaskItem(
                                id: task.id, label: updated.label, prompt: updated.prompt,
                                hour: updated.hour, minute: updated.minute,
                                repeatMode: updated.repeatMode, customDays: updated.customDays,
                                enabled: task.enabled, createdAt: task.createdAt,
                                lastFiredAt: task.lastFiredAt,
                                lastResultPreview: task.lastResultPreview,
                                lastResultSessionId: task.lastResultSessionId
                            )
                        } ?? updated
                        scheduler.upsert(withID)
                        path = NavigationPath()
                    }
                )
            }
        }
    }
}

/// Single row: label, schedule, next fire, enabled switch.
private struct ScheduledTaskRow: View {
    @StateObject private var scheduler = ScheduledTaskScheduler.shared
    let task: ScheduledTaskItem

    private var nextText: String {
        guard let next = ScheduledTaskItem.nextTriggerDate(task, from: Date()) else { return "—" }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: next)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.label)
                    .font(.body)
                    .foregroundStyle(task.enabled ? .primary : .secondary)
                Text(scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Next: \(nextText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let stamp = task.lastFiredAt {
                    Text("Last ran \(Date(timeIntervalSince1970: stamp).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { task.enabled },
                set: { newValue in scheduler.setEnabled(task.id, newValue) }
            ))
            .labelsHidden() // enabled state owned by store
        }
        .padding(.vertical, 2)
    }

    private var scheduleDescription: String {
        let hm = String(format: "%02d:%02d", task.hour, task.minute)
        switch task.repeatMode {
        case "daily": return "每天 \(hm)"
        case "weekdays": return "工作日 \(hm)"
        case "custom":
            let names = task.customDays.map(Self.weekdayShort).joined(separator: " ")
            return "\(names) \(hm)"
        default: return "单次 \(hm)"
        }
    }

    private static func weekdayShort(_ day: Int) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let idx = max(1, min(7, day))
        return "周\(names[idx - 1])"
    }
}

/// Editor used for both create (task == nil) and edit (task != nil).
struct ScheduledTaskEditorView: View {
    let task: ScheduledTaskItem?
    let onSave: (ScheduledTaskItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var prompt = ""
    @State private var time = Date()
    @State private var repeatMode = "daily"
    @State private var customDays: Set<Int> = [2, 3, 4, 5, 6] // Mon–Fri default
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") { TextField("e.g. 每日早报", text: $label) }
                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 90)
                    Text("Runs in a fresh chat each time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Time") { DatePicker("Run at", selection: $time, displayedComponents: .hourAndMinute) }
                Section("Repeat") {
                    Picker("Repeat", selection: $repeatMode) {
                        Text("Once").tag("once")
                        Text("Daily").tag("daily")
                        Text("Weekdays (Mon-Fri)").tag("weekdays")
                        Text("Custom days").tag("custom")
                    }
                    if repeatMode == "custom" {
                        HStack(spacing: 6) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                dayButton(day)
                            }
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "New Scheduled Task" : "Edit Scheduled Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                if let task {
                    label = task.label
                    prompt = task.prompt
                    var comps = DateComponents(); comps.hour = task.hour; comps.minute = task.minute
                    time = Calendar.current.date(from: comps) ?? Date()
                    repeatMode = task.repeatMode
                    customDays = Set(task.customDays)
                }
            }
            .alert("Missing Info", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Label and prompt are required.")
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let name = ScheduledTaskRow.WeekdayName(day)
        return Button(action: {
            if customDays.contains(day) { customDays.remove(day) } else { customDays.insert(day) }
        }) {
            Text(name)
                .font(.caption)
                .frame(width: 36, height: 30)
                .background(customDays.contains(day) ? Color.accentColor : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(customDays.contains(day) ? .white : .secondary)
        }
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedPrompt.isEmpty else { showError = true; return }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0

        let storedDays: [Int] = (repeatMode == "custom") ? customDays.sorted() : []
        let result = ScheduledTaskItem(
            label: trimmedLabel,
            prompt: trimmedPrompt,
            hour: hour,
            minute: minute,
            repeatMode: repeatMode,
            customDays: storedDays,
            enabled: true
        )
        onSave(result)
        dismiss()
    }
}

extension ScheduledTaskRow {
    static func WeekdayName(_ day: Int) -> String {
        return ScheduledTaskRow.weekdayShort(day).replacingOccurrences(of: "周", with: "")
    }
}