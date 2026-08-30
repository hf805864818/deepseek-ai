package com.openminis.app.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openminis.app.ui.theme.ChatColors

// MARK: - PlanGateConfirmationBar
// [T-deep-mode-ui-plangate] Plan confirmation bar shown when the agent
// proposes a plan and waits for user approval before executing.

@Composable
fun PlanGateConfirmationBar(
    viewModel: ChatViewModel,
    modifier: Modifier = Modifier,
) {
    val planGateState by viewModel.planGateState.collectAsState()
    val isVisible = planGateState == com.openminis.app.agent.PlanGate.State.AWAITING_APPROVAL

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
                        color = Color(0xFFFF9500).copy(alpha = 0.3f),
                        shape = RoundedCornerShape(12.dp),
                    )
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Icon
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .background(
                            Color(0xFFFF9500).copy(alpha = 0.15f),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.AutoAwesome,
                        contentDescription = null,
                        tint = Color(0xFFFF9500),
                        modifier = Modifier.size(18.dp),
                    )
                }

                Spacer(modifier = Modifier.width(10.dp))

                // Text content
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "深度模式 · 执行计划",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ChatColors.primaryText,
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "AI 已生成执行计划，请确认后开始执行",
                        fontSize = 11.sp,
                        color = ChatColors.secondaryText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                // Actions
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(
                        onClick = { viewModel.rejectPlan() },
                        modifier = Modifier.height(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "取消",
                            fontSize = 12.sp,
                        )
                    }
                    TextButton(
                        onClick = { viewModel.approvePlan() },
                        modifier = Modifier.height(32.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "执行",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

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
