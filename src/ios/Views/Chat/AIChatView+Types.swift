import AVFoundation
import Combine
import SwiftUI
import UIKit

private let minisLogger = AppLogger(category: "MinisURL")

// MARK: - Cached ViewModel

/// Wrapper that resolves an AIChatViewModel from the cache.
/// Used as @StateObject so SwiftUI creates it once per AIChatView lifetime,
/// but the underlying `vm` is the cached (possibly still-running) instance.
@MainActor
final class CachedViewModel: ObservableObject {
    let vm: AIChatViewModel
    /// True if this ViewModel was freshly created (not found in cache).
    let isNew: Bool
    /// Forwards the VM's objectWillChange to this wrapper so SwiftUI
    /// observes all @Published changes through the @StateObject.
    private var cancellable: AnyCancellable?

    init(sessionId: String?) {
        if let sessionId {
            let (cached, isNew) = ViewModelCache.shared.getOrCreate(for: sessionId)
            self.vm = cached
            self.isNew = isNew
            // If the cached VM is stale (iCloud merged new MessageV2 rows
            // for this session while we were on a DIFFERENT session and
            // the foreground reload signal never reached us), trigger a
            // fresh loadSession so the bubble list matches SQLite
            // (T-inbound-message-cached-vm-stale). Cache HIT only —
            // `isNew` already loads from scratch.
            if !isNew, ViewModelCache.shared.consumeStaleFlag(sessionId: sessionId) {
                minisLogger.info("🔑DRAFT CachedViewModel.init sessionId=\(sessionId) — STALE flag consumed, scheduling reload")
                Task { @MainActor [weak vm = cached] in
                    await vm?.loadSession()
                }
            }
            var logMsg = "🔑DRAFT CachedViewModel.init sessionId="
            logMsg += sessionId
            logMsg += " vm="
            logMsg += String(describing: cached.vmInstanceId)
            logMsg += " isNew="
            logMsg += String(isNew)
            minisLogger.info(logMsg)
        } else {
            let draft = ViewModelCache.shared.createDraft()
            self.vm = draft
            self.isNew = true
            var logMsg = "🔑DRAFT CachedViewModel.init DRAFT vm="
            logMsg += String(describing: draft.vmInstanceId)
            minisLogger.info(logMsg)
        }
        // Forward VM's objectWillChange → this wrapper's objectWillChange
        // so that SwiftUI re-renders when any @Published property on `vm` changes.
        cancellable = vm.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }

        // iOS 16 fix: When NavigationStack recreates the @StateObject, the new
        // CachedViewModel may wrap a VM that already has messages loaded. Force
        // a re-render so SwiftUI picks up the current state, since objectWillChange
        // events between the old and new subscription may have been lost.
        if !isNew {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
}

// MARK: - Color Palette (clean light theme)

enum ChatColors {
    static let background = Color(UIColor.systemBackground)
    static let secondaryBg = Color(UIColor.secondarySystemBackground)
    static let inputIconBg = Color(UIColor.secondarySystemBackground)
    static let inputIconBorder = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.35, alpha: 1) : UIColor(white: 0, alpha: 0) })
    static let inputBg = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : .white })
    static let inputBorder = Color(UIColor.separator)
    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    static let userBubble = Color(UIColor.tertiarySystemFill)
    static let toolBg = Color(UIColor.tertiarySystemGroupedBackground)
    static let toolBorder = Color(UIColor.separator).opacity(0.5)
    static let accent = Color(UIColor.label)
    static let sendButton = Color(UIColor.label)
    static let sendButtonDisabled = Color(UIColor.quaternaryLabel)
    /// Semantic "success / completed" color. Used for done state glyphs (e.g.
    /// workflow step tracker) so a change of success-color is one centralized
    /// edit instead of scattered hard-coded `.green` literals.
    static let success = Color(UIColor.systemGreen)
}

// MARK: - System Resource Monitor

class SystemResourceMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0     // 0-100
    @Published var memUsed: UInt64 = 0      // bytes
    @Published var memTotal: UInt64 = 0     // bytes
    private var timer: Timer?
    private var prevCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func start() {
        sampleCPU() // prime the previous ticks
        updateMemory()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sampleCPU()
                self?.updateMemory()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sampleCPU() {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let cur = (user: loadInfo.cpu_ticks.0, system: loadInfo.cpu_ticks.1, idle: loadInfo.cpu_ticks.2, nice: loadInfo.cpu_ticks.3)
        if let prev = prevCPUTicks {
            let userD = Double(cur.user &- prev.user)
            let sysD = Double(cur.system &- prev.system)
            let idleD = Double(cur.idle &- prev.idle)
            let niceD = Double(cur.nice &- prev.nice)
            let total = userD + sysD + idleD + niceD
            if total > 0 {
                cpuUsage = ((userD + sysD + niceD) / total) * 100
            }
        }
        prevCPUTicks = cur
    }

    private func updateMemory() {
        // App memory: internal + compressed (excludes external mappings like mmap/IOKit)
        // This matches Xcode's Memory Gauge more closely than phys_footprint
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        if result == KERN_SUCCESS {
            memUsed = UInt64(info.internal) + UInt64(info.compressed)
        }
        memTotal = ProcessInfo.processInfo.physicalMemory
    }

    var formattedCPU: String {
        String(format: "CPU %2.0f%%", cpuUsage)
    }

    func formattedMem(compact: Bool = false) -> String {
        let usedGB = Double(memUsed) / 1_073_741_824
        if compact {
            return String(format: "MEM %.1fG", usedGB)
        }
        let totalGB = Double(memTotal) / 1_073_741_824
        return String(format: "MEM %.1f/%.1f GB", usedGB, totalGB)
    }
}
