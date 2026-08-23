import SwiftUI

// [T-deep-mode-workflow] Phase 1 visualization feedback. Pure, state-free
// subviews driven by the VM's `workflowPhase` / `workflowSteps`. They hold no
// state of their own and NEVER render when deep mode is off — the host gates on
// `vm.deepModeEnabled` up the tree, so disabling the master switch removes all
// workflow UI with zero residue.

extension WorkflowPhase {
    /// Short human label for the current phase.
    var label: String {
        switch self {
        case .idle: return "空闲"
        case .planning: return "规划中"
        case .executing: return "执行中"
        case .verifying: return "复查中"
        }
    }

    /// SF Symbol paired with each phase.
    var symbolName: String {
        switch self {
        case .idle: return "circle.dashed"
        case .planning: return "list.bullet.rectangle"
        case .executing: return "gearshape.2"
        case .verifying: return "checkmark.circle.fill"
        }
    }
}

/// Compact vertical list of workflow steps with a per-step status glyph.
/// Rendered during both the planning (all-pending) and executing phases.
struct WorkflowStepsList: View {
    let steps: [WorkflowStep]

    var body: some View {
        Group {
            if steps.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            statusGlyph(step.status)
                                .frame(width: 14)
                            Text(step.title)
                                .font(.caption2)
                                .foregroundColor(step.status == .done
                                                 ? ChatColors.secondaryText
                                                 : ChatColors.primaryText)
                                .strikethrough(step.status == .done)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusGlyph(_ status: WorkflowStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundColor(ChatColors.secondaryText)
        case .active:
            Image(systemName: "arrow.forward.circle.fill")
                .font(.caption2)
                .foregroundColor(.accentColor)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(ChatColors.success)
        }
    }
}

/// Executing-phase progress bar: phase chip + step list + a "done/total" count.
/// The planning phase reuses `WorkflowStepsList` directly above its confirm bar.
struct WorkflowProgressView: View {
    let phase: WorkflowPhase
    let steps: [WorkflowStep]

    private var doneCount: Int {
        steps.filter { $0.status == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: phase.symbolName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("深度龙虾Ai · \(phase.label)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ChatColors.primaryText)
                Spacer(minLength: 8)
                if phase == .executing || phase == .verifying {
                    Text("\(doneCount)/\(steps.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(ChatColors.secondaryText)
                }
            }
            WorkflowStepsList(steps: steps)
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