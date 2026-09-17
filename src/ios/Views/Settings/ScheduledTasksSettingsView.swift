import SwiftUI

/// [T-deep-mode-phase-e] List + manage scheduled tasks (iOS).
///
/// Entry point from Settings → Agent Runtime → 定时任务. Mirrors the
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
                    VStack(spacing: 10) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("暂无定时任务")
                            .font(.headline)
                        Text("在深度龙虾AI里让它设置重复任务，例如「每天 9 点生成日报」，任务会显示在这里并自动运行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                    .padding(.horizontal, 24)
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
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        #endif
                    }
                }
            }
            .navigationTitle("定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingTask = nil
                        showingEditor = true
                    } label: {
                        Label("新建", systemImage: "plus")
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
                Text("下次运行：\(nextText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let stamp = task.lastFiredAt {
                    Text("上次运行 \(Date(timeIntervalSince1970: stamp).formatted(date: .abbreviated, time: .shortened))")
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
                Section("名称") { TextField("例如：每日早报", text: $label) }
                Section("指令") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 90)
                    Text("每次都会开启一个新会话执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("时间") { DatePicker("运行时间", selection: $time, displayedComponents: .hourAndMinute) }
                Section("重复") {
                    Picker("重复", selection: $repeatMode) {
                        Text("仅一次").tag("once")
                        Text("每天").tag("daily")
                        Text("工作日（周一至周五）").tag("weekdays")
                        Text("自定义日期").tag("custom")
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
            .navigationTitle(task == nil ? "新建定时任务" : "编辑定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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
            .alert("信息不完整", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text("名称和指令为必填项。")
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