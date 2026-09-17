import SwiftUI

// MARK: - Deep Mode Banners
// [T-deep-mode-workflow] Banner views for the deep-mode workflow gates.
// Pure, state-free — driven entirely by data passed in from the parent.
// Total-switch safe: these are only rendered when deep mode is on;
// the parent gates on `vm.deepModeEnabled` up the tree.
//
// Design: matches the WorkflowProgressView aesthetic — small SF Symbols,
// caption fonts, ChatColors palette. Each banner sits on a secondary
// background with a bottom hairline border.

// MARK: - ClarifyBanner

/// [T-deep-mode-clarify-gate] Banner shown when the deep-mode clarifier
/// detected ambiguity in the user's request. Asks a clarifying question
/// with cancel / skip actions.
struct ClarifyBanner: View {
    let question: String
    let onCancel: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("深度龙虾Ai · 需要澄清")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ChatColors.primaryText)
                Spacer(minLength: 8)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(ChatColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
            Text(question)
                .font(.caption2)
                .foregroundColor(ChatColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                Button(action: onSkip) {
                    Text("直接执行")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Text("或在下方输入答复后发送")
                    .font(.caption2)
                    .foregroundColor(ChatColors.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatColors.secondaryBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ChatColors.toolBorder).frame(height: 0.5)
        }
    }
}

// MARK: - PlanGateBanner

/// [T-deep-mode-plan-gate] Confirm/edit bar rendered above the messages
/// while a deep-mode plan is awaiting approval. Shows edit / confirm /
/// cancel actions.
struct PlanGateBanner: View {
    let onEdit: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("深度龙虾Ai · 已拟定执行计划")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ChatColors.primaryText)
                Text("确认后开始执行，或修改计划细节")
                    .font(.caption2)
                    .foregroundColor(ChatColors.secondaryText)
            }
            Spacer(minLength: 8)
            Button(action: onEdit) {
                Text("修改")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Button(action: onConfirm) {
                Text("确认执行")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(ChatColors.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatColors.secondaryBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ChatColors.toolBorder).frame(height: 0.5)
        }
    }
}

// MARK: - DeepModeWorkflowBanner

/// [T-deep-mode-workflow] Top-level container for all deep-mode workflow
/// UI that appears above the message list. Hard-gated on `deepModeEnabled`
/// so turning deep mode off removes ALL workflow UI with zero residue.
///
/// Contains, in order:
///   - Clarify banner (awaitingClarification)
///   - Plan steps + plan gate banner (awaitingApproval)
///   - Workflow progress view (executing / verifying)
///   - Subagent card stack (active subagents)
///
/// Extracted to a separate struct to cut the type tree at a struct boundary.
/// Without this, the deep-mode conditional branches would significantly
/// deepen AIChatView.body's mangled type, causing Swift's runtime type
/// decoder to recurse past its stack limit on cold launch.
struct DeepModeWorkflowBanner: View {
    let deepModeEnabled: Bool
    let clarifyState: ClarifyGate.State
    let activeSubagents: [SubagentSession]

    // Actions — only used when the corresponding state is active.
    let onCancelClarification: () -> Void
    let onSkipClarification: () -> Void

    var body: some View {
        Group {
            if deepModeEnabled {
                if case .awaitingClarification(let question, _) = clarifyState {
                    ClarifyBanner(
                        question: question,
                        onCancel: onCancelClarification,
                        onSkip: onSkipClarification
                    )
                }
            }
            if deepModeEnabled && !activeSubagents.isEmpty {
                SubagentCardStack(subagents: activeSubagents)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - FloatingWorkflowCapsule

/// [T-deep-mode-floating-panel] Right-edge floating execution progress
/// capsule. Collapsed by default it shows a compact chip ("0/7", gear icon,
/// phase label); tapping expands a live progress card with the step list and
/// real-time done/total count. When every step completes it auto-collapses
/// back to the icon and is torn down by the host once `workflowSteps` empties.
///
/// Total-switch safe: the host only renders it while deep mode is on AND the
/// workflow is mid-execution/verification, and `resetWorkflow()` flips the
/// phase to `.idle`, so disabling deep mode destroys it with zero residue.
struct FloatingWorkflowCapsule: View {
    let phase: WorkflowPhase
    let steps: [WorkflowStep]
    /// [T-deep-mode-session-workflow] P2b: true while an agent round is
    /// actively executing (the VM's `workflowBusy`, gated on the master switch
    /// up the tree). Drives a gentle pulse on the collapsed chip so a long
    /// high-cost tool call does not read as a frozen "0/x".
    var busy: Bool = false

    /// [T-deep-mode-panel-anchor] The toggle chip is pinned near the download
    /// button and stays put whether the panel is shown or hidden; the expanded
    /// panel lives in its own `FloatingWorkflowPanel` docked at the top.
    /// Tapping the chip flips this shared binding.
    @Binding var isExpanded: Bool

    @State private var pulsing = false

    private var doneCount: Int { steps.filter { $0.status == .done }.count }
    private var allDone: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .done } }

    var body: some View {
        collapsedChip
        // [T-deep-mode-session-workflow] Audit M1: auto-collapse only when the
        // task TRULY completes (phase enters .verifying via completeWorkflow).
        // Collapsing on `allDone` alone is wrong now that event-level progress
        // can mark every step done mid-run (before the final nudge round ends),
        // which would make the capsule pre-collapse while work is still running.
        .onChange(of: phase) { newPhase in
            if newPhase == .verifying {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isExpanded = false }
            }
        }
        // [T-deep-mode-session-workflow] P2b: start/stop the activity pulse in
        // sync with the master-switch-gated busy signal.
        .onAppear { syncPulse(busy) }
        .onChange(of: busy) { syncPulse($0) }
    }

    /// Drive the pulse only while work is genuinely in flight; otherwise settle.
    private func syncPulse(_ b: Bool) {
        if b {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { pulsing = false }
        }
    }

    /// Scale applied to the activity glyph when busy — a subtle breathing pulse.
    private var glyphScale: CGFloat { pulsing ? 1.18 : 1.0 }
    private var glyphOpacity: Double { pulsing ? 0.7 : 1.0 }

    private var collapsedChip: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: allDone ? "checkmark.circle.fill" : phase.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .scaleEffect(glyphScale)
                    .opacity(glyphOpacity)
                Text("\(doneCount)/\(steps.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundColor(ChatColors.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ChatColors.secondaryBg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ChatColors.toolBorder, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FloatingWorkflowPanel

/// [T-deep-mode-panel-anchor] The expanded task-progress popup. Docked at the
/// top (its long-standing position) by the host; independent of the toggle chip
/// so the popup never shifts when the chip is repositioned.
struct FloatingWorkflowPanel: View {
    let phase: WorkflowPhase
    let steps: [WorkflowStep]

    private var doneCount: Int { steps.filter { $0.status == .done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: phase.symbolName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("深度龙虾Ai · \(phase.label)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ChatColors.primaryText)
                Spacer(minLength: 8)
                Text("\(doneCount)/\(steps.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(ChatColors.secondaryText)
            }
            // Bounded + internally scrollable so a long step list stays a
            // compact top card (keeping the popup at its original docked
            // position) instead of growing down to the input/chip area.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    WorkflowStepsList(steps: steps)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 260, alignment: .leading)
        .background(ChatColors.secondaryBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ChatColors.toolBorder, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
    }
}

// MARK: - BannerHeightPreferenceKey

/// [T-deep-mode-banner-height] Preference key to report the height of the deep-mode banner stack so the floating progress panel can offset below it.
struct BannerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - FloatingConfirmPanel

/// [T-deep-mode-floating-panel] Trae-style floating confirmation panel for
/// the deep-mode plan gate. Docked ABOVE the input bar (the host pads it by
/// `inputBarHeight`), so it never covers the top dispatch pills nor the
/// composer text. Contains the parsed plan steps in a scrollable list plus
/// edit / confirm / cancel actions.
///
/// Multi-path plans (C12) additionally render a Trae-style multi-select of
/// candidate paths: each card shows the path title, risk badge and rationale
/// with a checkbox; tapping toggles it. The model's recommended path is
/// pre-selected on appearance (an empty selection still means "use the
/// recommended path" at the ViewModel layer, so unchecking all is safe).
///
/// Total-switch safe: the host gates on `deepModeEnabled` AND
/// `planGateState == .awaitingApproval`, and `resetWorkflow()` flips the
/// gate to `.idle` on toggle-off, so this view never renders after disable.
struct FloatingConfirmPanel: View {
    let steps: [WorkflowStep]
    let paths: [CandidatePath]
    let recommendedIndex: Int
    @Binding var selectedPathIndexes: Set<Int>
    let onEdit: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var hasChoices: Bool { !paths.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: title + dismiss.
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("深度龙虾Ai · 已拟定执行计划")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ChatColors.primaryText)
                    Text(hasChoices ? "可选择执行方案后确认，或修改计划细节" : "确认后开始执行，或修改计划细节")
                        .font(.caption2)
                        .foregroundColor(ChatColors.secondaryText)
                }
                Spacer(minLength: 8)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(ChatColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Scrollable content — long plans / many paths scroll, never cover input text.
            if !paths.isEmpty || !steps.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !paths.isEmpty {
                            pathPicker
                        }
                        if !steps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                WorkflowStepsList(steps: steps)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }

            // Action row.
            Divider()
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                Button(action: onEdit) {
                    Text("修改")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 420)
        .background(ChatColors.secondaryBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatColors.toolBorder, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 5)
        .onAppear {
            // Pre-select the model's recommended path so the user can confirm
            // directly; toggling works card-by-card afterwards. Guards against
            // an out-of-range recommendedIndex from a mislabeled plan.
            if !paths.isEmpty, selectedPathIndexes.isEmpty,
               paths.contains(where: { $0.index == recommendedIndex }) {
                selectedPathIndexes = [recommendedIndex]
            }
        }
    }

    /// Trae-style multi-select of candidate paths (C12).
    private var pathPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可选执行方案")
                .font(.caption2.weight(.semibold))
                .foregroundColor(ChatColors.secondaryText)
            ForEach(paths) { path in
                pathCard(path)
            }
        }
    }

    private func pathCard(_ path: CandidatePath) -> some View {
        let isSelected = selectedPathIndexes.contains(path.index)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isSelected {
                    selectedPathIndexes.remove(path.index)
                } else {
                    selectedPathIndexes.insert(path.index)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? .accentColor : ChatColors.secondaryText)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("路径 \(path.index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        Text(path.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ChatColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        riskBadge(path.riskLevel)
                    }
                    if !path.rationale.isEmpty {
                        Text(path.rationale)
                            .font(.caption2)
                            .foregroundColor(ChatColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : ChatColors.secondaryBg.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : ChatColors.toolBorder,
                            lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func riskBadge(_ risk: CandidatePath.RiskLevel) -> some View {
        let color: Color
        let label: String
        switch risk {
        case .low: color = .green; label = "低风险"
        case .medium: color = .orange; label = "中风险"
        case .high: color = .red; label = "高风险"
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var confirmLabel: String {
        guard hasChoices, selectedPathIndexes.count > 1 else { return "确认执行" }
        return "确认执行（\(selectedPathIndexes.count)）"
    }
}

// MARK: - SpecReviewPanel

/// [T-deep-mode-phase-f] Floating review panel for the spec documents the
/// model produced in the spec-writing phase. Docked above the input bar like
/// the plan gate. Offers Approve / Edit / Reject. Pure and state-free — driven
/// entirely by the VM's `pendingSpecFiles`. Only rendered when the parent sees
/// `deepModeEnabled && workflowPhase == .specReviewing`, so disabling the
/// master switch / Spec mode removes it with zero residue.
struct SpecReviewPanel: View {
    let files: [SpecGate.SpecFile]
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("深度龙虾Ai · 规格文档待审核")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ChatColors.primaryText)
                    Text("模型已将完成的成果整理为规格文档，请审阅")
                        .font(.caption2)
                        .foregroundColor(ChatColors.secondaryText)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if files.isEmpty {
                        Label("未检测到规格文档文件（path 未回显）", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(files) { file in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "doc")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.fileName)
                                        .font(.caption)
                                        .foregroundColor(ChatColors.primaryText)
                                    if !(file.path).isEmpty {
                                        Text((file.path as NSString).deletingLastPathComponent)
                                            .font(.caption2)
                                            .foregroundColor(ChatColors.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)

            Divider()
            HStack(spacing: 10) {
                Button(action: onReject) {
                    Text("拒绝")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ChatColors.secondaryText)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Button(action: onEdit) {
                    Text("修改")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Button(action: onApprove) {
                    Text("批准")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 420)
        .background(ChatColors.secondaryBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatColors.toolBorder, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 5)
    }
}
