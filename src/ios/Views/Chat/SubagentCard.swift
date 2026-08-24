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
        Self.symbolName(for: status)
    }

    static func symbolName(for status: SubagentStatus) -> String {
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
                    .modifier(BounceSymbolModifier(value: status))
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

// MARK: - BounceSymbolModifier

/// Wrapper for `.symbolEffect(.bounce:)` with iOS 17+ availability guard.
/// On iOS 16 and below, this is a no-op — the icon just doesn't bounce.
private struct BounceSymbolModifier: ViewModifier {
    let value: SubagentStatus

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

// MARK: - SubagentCard (Capsule Style)

/// A capsule-shaped subagent status pill, matching the ToolCapsuleView
/// aesthetic. Shown in a floating stack at the top of the chat area.
struct SubagentCard: View {
    @ObservedObject var subagent: SubagentSession

    private var iconColor: Color {
        switch subagent.status {
        case .pending:    return ChatColors.tertiaryText
        case .running:    return Color.accentColor
        case .completed:  return ChatColors.success
        case .failed:     return Color(UIColor.systemRed)
        case .cancelled:  return ChatColors.tertiaryText
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Status icon
            Group {
                if subagent.status == .running {
                    Image(systemName: "gearshape.2")
                        .modifier(BounceSymbolModifier(value: subagent.status))
                } else {
                    Image(systemName: SubagentStatusBadge.symbolName(for: subagent.status))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(iconColor)

            // Task description
            Text(subagent.taskDescription)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ChatColors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            // Progress or result
            if subagent.status == .running {
                Text("\(subagent.toolCallCount)/\(subagent.maxToolCalls)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(ChatColors.tertiaryText)
            } else if subagent.isFinished && !subagent.resultSummary.isEmpty {
                Text(subagent.resultSummary)
                    .font(.system(size: 11))
                    .foregroundColor(ChatColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color(UIColor.systemGray6))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(ChatColors.toolBorder, lineWidth: 0.5)
        )
        .contentShape(Capsule())
    }
}

// MARK: - SubagentCardStack

/// A floating vertical stack of SubagentCards for all active subagents.
/// Rendered by AIChatView as a top overlay when `deepModeEnabled` and there
/// are active subagent sessions. Total-switch safe: only shown when deep mode
/// is on and activeSubagents is non-empty. When the master switch is off,
/// activeSubagents is cleared in deepModeDidDisableCleanup, so this view
/// simply never appears.
struct SubagentCardStack: View {
    let subagents: [SubagentSession]

    var body: some View {
        if subagents.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 4) {
                ForEach(subagents) { subagent in
                    SubagentCard(subagent: subagent)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
