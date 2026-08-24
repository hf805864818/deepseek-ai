import SwiftUI

// MARK: - SubagentCard
// [T-phase5] Phase 5 visualization: a compact card showing the status of
// active subagent sessions. Pure, state-free — driven entirely by the
// SubagentSession's @Published properties. Total-switch safe: the host
// gates on `vm.deepModeEnabled`, so disabling the master switch removes
// all subagent UI with zero residue (the array is also cleared in
// deepModeDidDisableCleanup).
//
// Design: matches the WorkflowProgressView aesthetic — small SF Symbols,
// caption2 fonts, ChatColors palette. No animations beyond standard SwiftUI
// transitions to keep the tool-call loop cheap.

// MARK: - SubagentStatusBadge

/// A small colored badge showing the subagent's current status.
/// Used inline in the SubagentCard and optionally in the FloatingToolBar.
struct SubagentStatusBadge: View {
    let status: SubagentStatus

    private var label: String {
        switch status {
        case .pending: return "等待"
        case .running: return "运行中"
        case .completed: return "完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private var symbolName: String {
        switch status {
        case .pending: return "circle.dashed"
        case .running: return "gearshape.2"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pending: return ChatColors.tertiaryText
        case .running: return Color.accentColor
        case .completed: return ChatColors.success
        case .failed: return Color(UIColor.systemRed)
        case .cancelled: return ChatColors.tertiaryText
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .medium))
                    .symbolEffect(.bounce, value: status)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - SubagentCard

/// A compact card showing a single subagent's status.
/// Shown in a VStack when one or more subagents are active.
struct SubagentCard: View {
    @ObservedObject var subagent: SubagentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: task description + status badge
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 12))
                    .foregroundColor(ChatColors.secondaryText)

                Text(subagent.taskDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ChatColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                SubagentStatusBadge(status: subagent.status)
            }

            // Progress: tool call count / max
            if subagent.status == .running {
                HStack(spacing: 4) {
                    Image(systemName: "hammer")
                        .font(.system(size: 10))
                        .foregroundColor(ChatColors.tertiaryText)
                    Text("\(subagent.toolCallCount)/\(subagent.maxToolCalls) tool calls")
                        .font(.system(size: 11))
                        .foregroundColor(ChatColors.tertiaryText)
                    if !subagent.lastActivity.isEmpty {
                        Text("· \(subagent.lastActivity)")
                            .font(.system(size: 11))
                            .foregroundColor(ChatColors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 20)
            }

            // Result summary (when finished)
            if subagent.isFinished && !subagent.resultSummary.isEmpty {
                Text(subagent.resultSummary)
                    .font(.system(size: 11))
                    .foregroundColor(ChatColors.secondaryText)
                    .lineLimit(3)
                    .padding(.leading, 20)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChatColors.toolBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ChatColors.toolBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - SubagentCardStack

/// A vertical stack of SubagentCards for all active subagents.
/// Rendered by AIChatView when `deepModeEnabled` and there are active subagents.
/// Total-switch safe: only shown when deep mode is on and activeSubagents is
/// non-empty. When the master switch is off, activeSubagents is cleared in
/// deepModeDidDisableCleanup, so this view simply never appears.
struct SubagentCardStack: View {
    let subagents: [SubagentSession]

    var body: some View {
        if subagents.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 6) {
                ForEach(subagents) { subagent in
                    SubagentCard(subagent: subagent)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
    }
}
