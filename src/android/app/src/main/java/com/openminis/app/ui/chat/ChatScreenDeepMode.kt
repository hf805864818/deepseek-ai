package com.openminis.app.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openminis.app.ui.theme.ChatColors

// MARK: - ClarifyGateBar
// [T-deep-mode-ui-clarifygate] Ambiguity clarification bar shown when the
// agent detects ambiguity in the user's request and asks for clarification.

@Composable
fun ClarifyGateBar(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val clarifyState by viewModel.clarifyState.collectAsState()
    val isVisible = clarifyState == com.openminis.app.agent.ClarifyGate.State.AWAITING_CLARIFICATION

    AnimatedVisibility(
        visible = isVisible,
        enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
        exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            ChatColors.background.copy(alpha = 0f),
                            ChatColors.background.copy(alpha = 0.95f),
                        ),
                    ),
                )
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(ChatColors.toolCapsuleBg)
                    .border(
                        width = 1.dp,
                        color = Color(0xFF007AFF).copy(alpha = 0.3f),
                        shape = RoundedCornerShape(12.dp),
                    )
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .background(
                            Color(0xFF007AFF).copy(alpha = 0.15f),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.HelpOutline,
                        contentDescription = null,
                        tint = Color(0xFF007AFF),
                        modifier = Modifier.size(18.dp),
                    )
                }

                Spacer(modifier = Modifier.width(10.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "需要澄清",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ChatColors.primaryText,
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "AI 对你的需求有疑问，请在输入框中补充说明",
                        fontSize = 11.sp,
                        color = ChatColors.secondaryText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                TextButton(
                    onClick = { viewModel.skipClarification() },
                    modifier = Modifier.height(32.dp),
                ) {
                    Text(
                        text = "跳过",
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
}

// MARK: - DeepModeBadge
// [T-deep-mode-ui-badge] Small badge in the top bar indicating that deep
// mode is active and showing the current intensity level.

@Composable
fun DeepModeBadge(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val deepModeLevel by viewModel.deepModeLevel.collectAsState()
    val deepModeEnabled = deepModeLevel != com.openminis.app.agent.DeepModeLevel.LITE

    if (!deepModeEnabled) return

    val tintColor = when (deepModeLevel) {
        com.openminis.app.agent.DeepModeLevel.AGGRESSIVE -> Color(0xFFFF9500)
        com.openminis.app.agent.DeepModeLevel.STANDARD -> Color(0xFF34C759)
        else -> Color(0xFF8E8E93)
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(tintColor.copy(alpha = 0.12f))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(
            imageVector = Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = tintColor,
            modifier = Modifier.size(11.dp),
        )
        Text(
            text = deepModeLevel.displayName,
            fontSize = 10.sp,
            fontWeight = FontWeight.Medium,
            color = tintColor,
        )
    }
}

// MARK: - NeedMoreContextBanner
// [T-deep-mode-ui-need-context] Banner shown when the agent stops because
// it needs more context from the user (C10: need_more_context sentinel).

@Composable
fun NeedMoreContextBanner(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val needMoreContext by viewModel.needMoreContextState.collectAsState()
    val isVisible = !needMoreContext.isNullOrBlank()

    AnimatedVisibility(
        visible = isVisible,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier,
    ) {
        val reason = needMoreContext ?: return@AnimatedVisibility
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(Color(0xFFFF9500).copy(alpha = 0.1f))
                .border(
                    width = 1.dp,
                    color = Color(0xFFFF9500).copy(alpha = 0.25f),
                    shape = RoundedCornerShape(10.dp),
                )
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                imageVector = Icons.Default.HelpOutline,
                contentDescription = null,
                tint = Color(0xFFFF9500),
                modifier = Modifier
                    .size(16.dp)
                    .padding(top = 1.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "需要更多信息",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ChatColors.primaryText,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = reason,
                    fontSize = 11.sp,
                    color = ChatColors.secondaryText,
                    lineHeight = 14.sp,
                )
            }
        }
    }
}

// MARK: - Workflow visual helpers
// [T-deep-mode-floating-panel] Shared phase label / icon mapping used by the
// floating confirm panel and the right-edge progress capsule. Mirrors the iOS
// `WorkflowPhase.label` / `symbolName` extension (WorkflowProgressView.swift).

private val phaseAccent = Color(0xFF007AFF)

private fun workflowPhaseLabel(phase: com.openminis.app.agent.WorkflowPhase): String = when (phase) {
    com.openminis.app.agent.WorkflowPhase.IDLE -> "空闲"
    com.openminis.app.agent.WorkflowPhase.PLANNING -> "规划中"
    com.openminis.app.agent.WorkflowPhase.EXECUTING -> "执行中"
    com.openminis.app.agent.WorkflowPhase.VERIFYING -> "复查中"
}

private fun workflowPhaseIcon(phase: com.openminis.app.agent.WorkflowPhase): ImageVector = when (phase) {
    com.openminis.app.agent.WorkflowPhase.IDLE -> Icons.Default.List
    com.openminis.app.agent.WorkflowPhase.PLANNING -> Icons.Default.List
    com.openminis.app.agent.WorkflowPhase.EXECUTING -> Icons.Default.Settings
    com.openminis.app.agent.WorkflowPhase.VERIFYING -> Icons.Default.CheckCircle
}

/// Compact vertical list of workflow steps with a per-step status glyph.
/// Completed steps use a BLUE checkmark ("完成一项就自动在任务前面打蓝色勾").
@Composable
private fun WorkflowStepsList(
    steps: List<com.openminis.app.agent.WorkflowStep>,
) {
    if (steps.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        steps.forEach { step ->
            Row(verticalAlignment = Alignment.Top) {
                val glyphColor: Color
                val glyphIcon: ImageVector
                when (step.status) {
                    com.openminis.app.agent.WorkflowStepStatus.PENDING -> {
                        glyphColor = ChatColors.secondaryText
                        glyphIcon = Icons.Default.List
                    }
                    com.openminis.app.agent.WorkflowStepStatus.ACTIVE -> {
                        glyphColor = phaseAccent
                        glyphIcon = Icons.Default.Settings
                    }
                    com.openminis.app.agent.WorkflowStepStatus.DONE -> {
                        glyphColor = phaseAccent
                        glyphIcon = Icons.Default.CheckCircle
                    }
                }
                Icon(
                    imageVector = glyphIcon,
                    contentDescription = null,
                    tint = glyphColor,
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .size(12.dp),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = step.title,
                    fontSize = 11.sp,
                    color = if (step.status == com.openminis.app.agent.WorkflowStepStatus.DONE) {
                        ChatColors.secondaryText
                    } else {
                        ChatColors.primaryText
                    },
                )
                Spacer(modifier = Modifier.width(4.dp))
            }
        }
    }
}

// MARK: - FloatingConfirmPanel
// [T-deep-mode-floating-panel] Trae-style floating confirmation panel for the
// deep-mode plan gate, docked ABOVE the composer (the host renders it at the
// top of the input column, so it never covers the composer text). Contains the
// parsed plan steps in a scrollable list plus confirm / reject actions.
//
// Multi-path plans (C12) additionally render a Trae-style multi-select of the
// candidate paths: each card shows the path title, risk badge and rationale
// with a checkbox; tapping toggles it. The model's recommended path is
// pre-selected by the ViewModel on detection (an empty selection still means
// "use the recommended path" at the ViewModel layer, so unchecking all is safe).
//
// Total-switch safe: only rendered while deep mode is on AND the plan gate is
// awaiting approval; disabling deep mode leaves `planGateState` at `.idle`, so
// this view never renders after toggle-off.

@Composable
fun FloatingConfirmPanel(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val deepModeEnabled by viewModel.deepModeEnabled.collectAsState()
    val planGateState by viewModel.planGateState.collectAsState()
    val isVisible = deepModeEnabled &&
        planGateState == com.openminis.app.agent.PlanGate.State.AWAITING_APPROVAL

    val paths by viewModel.pendingPlanPaths.collectAsState()
    val recommendedIndex by viewModel.pendingRecommendedIndex.collectAsState()
    val selectedIndexes by viewModel.selectedPathIndexes.collectAsState()
    val workflowSteps by viewModel.workflowSteps.collectAsState()

    // The ViewModel pre-selects the recommended path on detection, but guard a
    // pathological out-of-range / empty selection so the user can still confirm.
    if (isVisible && paths.isNotEmpty() && selectedIndexes.isEmpty() &&
        paths.any { it.index == recommendedIndex }
    ) {
        LaunchedEffect(recommendedIndex) {
            viewModel.setSelectedPathIndexes(setOf(recommendedIndex))
        }
    }

    AnimatedVisibility(
        visible = isVisible,
        enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
        exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
        modifier = modifier,
    ) {
        val hasChoices = paths.isNotEmpty()
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 320.dp)
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            ChatColors.background.copy(alpha = 0f),
                            ChatColors.background.copy(alpha = 0.97f),
                        ),
                    ),
                )
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(ChatColors.toolCapsuleBg)
                    .border(
                        width = 1.dp,
                        color = ChatColors.toolBorder.copy(alpha = 0.7f),
                        shape = RoundedCornerShape(14.dp),
                    ),
            ) {
                // Header row: title + dismiss.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        tint = phaseAccent,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "深度龙虾Ai · 已拟定执行计划",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = ChatColors.primaryText,
                        )
                        Text(
                            text = if (hasChoices) {
                                "可选择执行方案后确认，或修改计划细节"
                            } else {
                                "确认后开始执行，或修改计划细节"
                            },
                            fontSize = 10.sp,
                            color = ChatColors.secondaryText,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    TextButton(
                        onClick = { viewModel.rejectPlan() },
                        modifier = Modifier
                            .size(30.dp)
                            .padding(0.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "关闭",
                            tint = ChatColors.secondaryText,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }

                // Scrollable content — long plans / many paths scroll inside a
                // bounded height and never cover the composer below.
                if (hasChoices || workflowSteps.isNotEmpty()) {
                    androidx.compose.material3.HorizontalDivider(
                        color = ChatColors.toolBorder.copy(alpha = 0.5f),
                    )
                    Column(
                        modifier = Modifier
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 14.dp, vertical = 6.dp),
                    ) {
                        if (hasChoices) {
                            Text(
                                text = "可选执行方案",
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = ChatColors.secondaryText,
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            paths.forEach { path ->
                                val isSelected = selectedIndexes.contains(path.index)
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(
                                            if (isSelected) phaseAccent.copy(alpha = 0.08f)
                                            else ChatColors.toolCapsuleBg.copy(alpha = 0.6f)
                                        )
                                        .border(
                                            width = if (isSelected) 1.dp else 0.5.dp,
                                            color = if (isSelected) phaseAccent.copy(alpha = 0.5f)
                                            else ChatColors.toolBorder.copy(alpha = 0.6f),
                                            shape = RoundedCornerShape(10.dp),
                                        )
                                        .clickable {
                                            viewModel.setSelectedPathIndexes(
                                                if (isSelected) selectedIndexes - path.index
                                                else selectedIndexes + path.index
                                            )
                                        }
                                        .padding(horizontal = 10.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.Top,
                                ) {
                                    Icon(
                                        imageVector = if (isSelected) Icons.Default.CheckCircle
                                        else Icons.Default.List,
                                        contentDescription = null,
                                        tint = if (isSelected) phaseAccent else ChatColors.secondaryText,
                                        modifier = Modifier
                                            .padding(top = 2.dp)
                                            .size(15.dp),
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(
                                                text = "路径 ${path.index}",
                                                fontSize = 9.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = phaseAccent,
                                                modifier = Modifier
                                                    .background(
                                                        phaseAccent.copy(alpha = 0.12f),
                                                        RoundedCornerShape(50),
                                                    )
                                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                                            )
                                            Spacer(modifier = Modifier.width(6.dp))
                                            Text(
                                                text = path.title.ifBlank { "执行方案 ${path.index}" },
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                color = ChatColors.primaryText,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.weight(1f, fill = false),
                                            )
                                            Spacer(modifier = Modifier.width(4.dp))
                                            val (riskText, riskColor) = riskPresentation(path.riskLevel)
                                            Text(
                                                text = riskText,
                                                fontSize = 9.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                color = riskColor,
                                                modifier = Modifier
                                                    .background(riskColor.copy(alpha = 0.12f), RoundedCornerShape(50))
                                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                                            )
                                        }
                                        if (path.rationale.isNotBlank()) {
                                            Spacer(modifier = Modifier.height(3.dp))
                                            Text(
                                                text = path.rationale,
                                                fontSize = 10.sp,
                                                color = ChatColors.secondaryText,
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        }
                                    }
                                }
                            }
                            if (workflowSteps.isNotEmpty()) {
                                Spacer(modifier = Modifier.height(10.dp))
                            }
                        }
                        WorkflowStepsList(steps = workflowSteps)
                    }
                    androidx.compose.material3.HorizontalDivider(
                        color = ChatColors.toolBorder.copy(alpha = 0.5f),
                    )
                }

                // Action row: confirm / reject.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(
                        onClick = { viewModel.rejectPlan() },
                        modifier = Modifier.height(30.dp),
                    ) {
                        Text(
                            text = "取消",
                            fontSize = 11.sp,
                            color = ChatColors.secondaryText,
                        )
                    }
                    Spacer(modifier = Modifier.width(4.dp))
                    TextButton(
                        onClick = { viewModel.approvePlan() },
                        modifier = Modifier
                            .height(32.dp)
                            .clip(RoundedCornerShape(50))
                            .background(phaseAccent)
                            .padding(horizontal = 4.dp),
                        colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
                            contentColor = Color.White,
                        ),
                    ) {
                        Text(
                            text = if (hasChoices && selectedIndexes.size > 1) {
                                "确认执行（${selectedIndexes.size}）"
                            } else {
                                "确认执行"
                            },
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

private fun riskPresentation(risk: com.openminis.app.agent.MultiPathPlanner.RiskLevel): Pair<String, Color> =
    when (risk) {
        com.openminis.app.agent.MultiPathPlanner.RiskLevel.LOW -> "低风险" to Color(0xFF34C759)
        com.openminis.app.agent.MultiPathPlanner.RiskLevel.MEDIUM -> "中风险" to Color(0xFFFF9500)
        com.openminis.app.agent.MultiPathPlanner.RiskLevel.HIGH -> "高风险" to Color(0xFFFF3B30)
    }

// MARK: - FloatingWorkflowCapsule
// [T-deep-mode-floating-panel] Right-edge floating execution progress capsule.
// Collapsed by default it shows a compact chip ("0/7", gear icon, phase label);
// tapping expands a live progress card with the step list and real-time
// done/total count. When every step completes it auto-collapses back to the
// icon and is torn down by the host once `workflowSteps` empties.
//
// Total-switch safe: the host only renders it while deep mode is on AND the
// workflow is mid-execution/verification; disabling deep mode resets the phase
// to `.idle`, so this view never renders after toggle-off.

@Composable
fun FloatingWorkflowCapsule(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val deepModeEnabled by viewModel.deepModeEnabled.collectAsState()
    val workflowPhase by viewModel.workflowPhase.collectAsState()
    val workflowSteps by viewModel.workflowSteps.collectAsState()

    // [T-deep-mode-session-workflow] P2b: activity pulse. While the agent loop
    // is actively executing (a long shell/file tool call), blink the collapsed
    // chip's glyph so a heavy step does not read as a frozen "0/x". The busy
    // flag is gated on the master switch (workflowBusy). Total-switch safe.
    val workflowBusy by viewModel.workflowBusy.collectAsState()
    val keepSessionWorkflow by viewModel.keepSessionWorkflow.collectAsState()
    // Activity pulse. Run the infinite animation only while the agent loop is
    // actually busy; when idle the transition is not composed at all, so no
    // frames are driven (Audit L3) and the glyph renders steady at 1f/1f.
    val busyScale: Float
    val busyAlpha: Float
    if (workflowBusy) {
        val busyPulse = rememberInfiniteTransition()
        val busyScaleAnim by busyPulse.animateFloat(
            initialValue = 1f,
            targetValue = 1.18f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 800),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "busyPulseScale",
        )
        val busyAlphaAnim by busyPulse.animateFloat(
            initialValue = 1f,
            targetValue = 0.7f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 800),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "busyPulseAlpha",
        )
        busyScale = busyScaleAnim
        busyAlpha = busyAlphaAnim
    } else {
        busyScale = 1f
        busyAlpha = 1f
    }
    val glyphScale = busyScale
    val glyphAlpha = busyAlpha

    val isVisible = deepModeEnabled &&
        keepSessionWorkflow &&
        (workflowPhase == com.openminis.app.agent.WorkflowPhase.EXECUTING ||
            workflowPhase == com.openminis.app.agent.WorkflowPhase.VERIFYING) &&
        workflowSteps.isNotEmpty()

    var isExpanded by remember { mutableStateOf(false) }
    val doneCount = workflowSteps.count { it.status == com.openminis.app.agent.WorkflowStepStatus.DONE }
    val allDone = workflowSteps.isNotEmpty() && workflowSteps.all {
        it.status == com.openminis.app.agent.WorkflowStepStatus.DONE
    }

    // Auto-collapse once the task TRULY completes, i.e. when the workflow enters
    // VERIFYING via completeWorkflowSteps. Do NOT collapse merely when the
    // incremental step state is all-done (which can happen transiently mid-run
    // due to event-level progress alongside round-boundary advances) — otherwise
    // the capsule pre-collapses while the final nudge round is still executing
    // (Audit M1).
    LaunchedEffect(workflowPhase) {
        if (workflowPhase == com.openminis.app.agent.WorkflowPhase.VERIFYING) isExpanded = false
    }

    AnimatedVisibility(
        visible = isVisible,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp)),
            verticalAlignment = Alignment.Top,
        ) {
            androidx.compose.animation.AnimatedVisibility(
                visible = isExpanded,
                enter = slideInVertically(initialOffsetY = { it / 2 }) + fadeIn(),
                exit = slideOutVertically(targetOffsetY = { it / 2 }) + fadeOut(),
            ) {
                Column(
                    modifier = Modifier
                        .width(260.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(ChatColors.toolCapsuleBg)
                        .border(
                            width = 1.dp,
                            color = ChatColors.toolBorder.copy(alpha = 0.7f),
                            shape = RoundedCornerShape(12.dp),
                        )
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = workflowPhaseIcon(workflowPhase),
                            contentDescription = null,
                            tint = phaseAccent,
                            modifier = Modifier.size(13.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "深度龙虾Ai · ${workflowPhaseLabel(workflowPhase)}",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = ChatColors.primaryText,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = "$doneCount/${workflowSteps.size}",
                            fontSize = 10.sp,
                            color = ChatColors.secondaryText,
                        )
                    }
                    WorkflowStepsList(steps = workflowSteps)
                }
            }
            Spacer(modifier = Modifier.width(6.dp))
            // Collapsed chip — always present so a tap toggles expansion.
            androidx.compose.material3.Surface(
                onClick = { isExpanded = !isExpanded },
                shape = RoundedCornerShape(50),
                color = ChatColors.toolCapsuleBg,
                border = androidx.compose.foundation.BorderStroke(
                    width = 1.dp,
                    color = ChatColors.toolBorder.copy(alpha = 0.8f),
                ),
                shadowElevation = 3.dp,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        imageVector = if (allDone) Icons.Default.CheckCircle else workflowPhaseIcon(workflowPhase),
                        contentDescription = null,
                        tint = phaseAccent,
                        // [T-deep-mode-session-workflow] P2b: breathing pulse while busy.
                        modifier = Modifier
                            .size(12.dp)
                            .scale(glyphScale)
                            .alpha(glyphAlpha),
                    )
                    Text(
                        text = "$doneCount/${workflowSteps.size}",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ChatColors.primaryText,
                    )
                }
            }
        }
    }
}
