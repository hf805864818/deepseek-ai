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
    let planGateState: PlanGate.State
    let workflowPhase: WorkflowPhase
    let workflowSteps: [WorkflowStep]
    let activeSubagents: [SubagentSession]

    // Actions — only used when the corresponding state is active.
    let onCancelClarification: () -> Void
    let onSkipClarification: () -> Void
    let onEditPlan: () -> Void
    let onConfirmPlan: () -> Void
    let onCancelPlan: () -> Void

    var body: some View {
        Group {
            if deepModeEnabled {
                if case .awaitingClarification(let question, _) = clarifyState {
                    ClarifyBanner(
                        question: question,
                        onCancel: onCancelClarification,
                        onSkip: onSkipClarification
                    )
                } else if case .awaitingApproval = planGateState {
                    VStack(alignment: .leading, spacing: 0) {
                        if !workflowSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("计划步骤")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(ChatColors.secondaryText)
                                WorkflowStepsList(steps: workflowSteps)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ChatColors.secondaryBg)
                        }
                        PlanGateBanner(
                            onEdit: onEditPlan,
                            onConfirm: onConfirmPlan,
                            onCancel: onCancelPlan
                        )
                    }
                } else if workflowPhase == .executing || workflowPhase == .verifying {
                    WorkflowProgressView(phase: workflowPhase,
                                         steps: workflowSteps)
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
