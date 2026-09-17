# 会话级工作流 + Goal 完成条件驱动续跑 改造方案

> 记录会话级（session-scoped）工作流改造的设计、实施与状态。全文以深度龙虾Ai 总开关（`deepModeEnabled`）为唯一门禁，任何路径不可越过。

## 背景与问题

在测试「A1. 单路径计划标准确认」时发现两个典型故障：

1. 最后一条 shell command 显示后，任务一直卡住不动 —— 模型在回合末尾忘了发出 `<<GOAL_STATE>>` 完成哨兵，客户端无法结算，胶囊停留在「执行中」。
2. 点暂停后悬浮缩略胶囊消失，继续任务后不再出现 —— 工作流状态是**请求级**的，暂停即销毁，续跑没有可恢复的 snapshot。

对比 Trae 的 Goal 工作流：Trae 将工作流状态与会话绑定，即使断流/暂停也能在目标达成前自动续跑。本改造目标即对齐该语义。

## 设计要点

- **会话级状态**：工作流 phase/steps/verify/goal 预算在会话内持续存在，而非单次请求内。
- **插话并入**：`.executing` / `.verifying` 阶段收到新用户消息时，不重置、不销毁，作为插话并入当前会话工作流。
- **暂停/续跑**：暂停（`cancelStream`）快照保存 `SavedWorkflowSnapshot`，续跑（`resume`）恢复，UI 胶囊不消失。
- **客户端完成评估器**：`<<GOAL_STATE>>` 哨兵不再被无条件信任 —— 增加确定性客户端评估，防止「最后一条 shell 后卡住」与「过早报 done」两类失败。
- **总开关门禁**：所有逻辑仅在 `deepModeEnabled` 路径内可达；开关关闭时 phase 恒为 `.idle`，一切退化为安全默认。

## 实施状态

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P0 | 发送路径会话级门禁（in-flight 走插话并入、不做重置）；Android 补齐 `cancelStream` 保存 / `resume` 恢复，对齐 iOS `savedWorkflowState`；计划门禁仅对 idle/planning 生效 | ✅ 已交付（`750cb6f`） |
| P1 | 新增 `GoalCompletionEvaluator`（双端），每轮结算做客户端确定性评估：所有步骤 done 且未发哨兵 → 自动收尾（防止胶囊卡/消失）；过早报 done 且步骤未完成 → 续跑兜底直至预算耗尽 | ✅ 已交付（`b5966b7`） |
| P2a | 会话级工作流回退开关 `keepSessionWorkflow`（默认开，双端），关闭即退回旧「每请求一工作流」行为，作风险熔断/灰度 | ✅ 已交付 |
| P2b | 进度反馈活动指示 `workflowBusy`：agent 回合执行期间胶囊图标脉冲/微旋转，消除「0/x 静止」卡死观感（已绑定 SwiftUI `FloatingWorkflowCapsule` 与 Compose `ChatScreenDeepMode`；事件级刷新作独立可选子项，未实施） | ✅ 已交付 |

## 关键文件

- iOS：`src/ios/Agent/Chat/AIChatViewModel.swift`、`src/ios/Agent/Chat/GoalRunner.swift`
- Android：`src/android/app/src/main/java/com/openminis/app/ui/chat/ChatViewModel.kt`、`src/android/app/src/main/java/com/openminis/app/agent/GoalRunner.kt`

## 门禁核验结论

- iOS：`inFlightWorkflow = deepModeEnabled && (executing || verifying)`，开关关时恒为 false → 走重置；P1 评估器仅在 `deepModeEnabled` 门禁内调用。
- Android：sentinel 解析包裹在 `deepModeOn` 门禁内；P1 两处评估均二次复核 `_deepModeEnabled.value`。
- 两端均为纯函数 + total-switch safe；续跑受 `goalRunnerRoundsLeft`（上限）约束，不会无限循环。