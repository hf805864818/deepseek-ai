# 深度龙虾Ai 元认知与自适应思维能力开发方案（v9.0）

> ⚠️ **【双端同步开发铁律】以后不管开发新功能还是做性能优化，iOS 和 Android 必须同时设计、同时开发、同时测试、同时上线。严禁只做一端、另一端滞后跟进的模式。两端功能差异不得超过一个小版本周期。**

> v9.0 —— 统一悬浮面板：确认面板与执行进度胶囊彻底分离，对齐 Trae 的多选决策交互。所有新增 UI 一律受 `deepModeEnabled` 总开关约束。

| 版本 | 日期 | 总开关控制 | 新增内容 |
|------|------|------------|----------|
| **v8.0 (双端对齐)** | 2026-08-29 | `deepModeEnabled` | Android 端 DeepMode 14项能力补全 + 双端增量构建等 |
| **v9.0 (统一悬浮面板)** | 2026-09-17 | `deepModeEnabled` | 确认弹窗与进度胶囊分离为独立悬浮组件；进度胶囊收缩到右上边缘图标并实时更新；确认面板从输入栏上方弹出、内容可滚动；多路径(C12)提供 Trae 风格多选勾选 |

---

## 目录

1. [v9.0 背景与需求](#一v90-背景与需求)
2. [三态生命周期设计](#二三态生命周期设计)
3. [组件与关键实现](#三组件与关键实现)
4. [多路径多选交互（C12 联动）](#四多路径多选交互c12-联动)
5. [总开关兼容性验证](#五总开关兼容性验证)
6. [改动文件清单](#六改动文件清单)
7. [待办与后续建议](#七待办与后续建议)

---

## 一、v9.0 背景与需求

v8.0 中，深度模式的任务确定弹窗（PlanGateBanner）与执行进度（WorkflowProgressView）是同一种内联横幅，叠加在消息列表上方。用户反馈三个体验问题：

1. **确认后弹窗不消失**：确认后内联横幅被进度视图原地替换，视觉上像是"卡住/残留"。
2. **确认与进度耦合**：用户期望"确认"与"查看进度"是两个相互独立的交互，确认后无需一直看到横幅。
3. **无多选交互**：C12 多路径计划只能展示推荐路径，缺少像 Trae 那样"遇到需要做选择时出现可勾选选项"的交互。

v9.0 据此将两者重构为两个自包含、互不干扰的悬浮组件，并对齐 Trae 的交互范式。

---

## 二、三态生命周期设计

| 状态 | UI | 触发 | 结束 |
|------|----|------|------|
| **确认（expanded）** | `FloatingConfirmPanel` 悬浮确认面板，停靠在输入栏上方 | PlanGate 进入 `.awaitingApproval` | 用户确认 / 修改 / 关闭 |
| **执行（collapsed）** | `FloatingWorkflowCapsule` 胶囊收缩到右上边缘 | 确认后进入 `.executing` / `.verifying` | 全部步骤完成 → 自动收起 |
| **销毁（destroyed）** | 无 | 确认完成 / 全部完成 / 关闭总开关 | 挂载视图随 `@Published` 状态归零卸载 |

要点：
- 确认后面板立即销毁，进度交给独立胶囊接管，二者永不同屏重叠。
- 进度胶囊默认只显示紧凑图标 + `done/total`（如 `0/7`）；点击展开实时步骤列表。
- 完成一项自动在任务前打蓝色勾；全部完成自动收起为图标，随后随状态复位消失。

---

## 三、组件与关键实现

### 3.1 `FloatingConfirmPanel`（悬浮确认面板）

- 通过宿主 `.overlay(alignment: .bottom)` 挂载，`padding(.bottom, inputBarHeight + 8)`，即从输入栏上方弹出，**不遮挡顶部派遣药丸，也不遮挡输入文字**。
- 内部为可滚动区域（`.frame(maxHeight: 240)`），内容过多时可上下滑动查看更多。
- Header 含标题 / 副标题 / 关闭按钮；底部操作行含「修改」「确认执行」。
- 生命周期按内容类型区分：
  - 纯计划 / 计划+选择 → 确认后面板销毁，进度由胶囊接管。
  - 纯选择（无跟踪步骤）→ 确认后仅销毁，无胶囊残留。

### 3.2 `FloatingWorkflowCapsule`（执行进度胶囊）

- 通过宿主 `.overlay(alignment: .topTrailing)` 挂载，默认收缩到右上边缘。
- 支持展开/收起切换；展开显示阶段标签 + `done/total` + 实时步骤列表（`WorkflowStepsList`）。
- 全部完成后用 `.onChange(of: allDone)` 自动收起。

### 3.3 视图模型接线

- 新增 `@Published var selectedPathIndexes: Set<Int> = []`，承载多选状态。
- `confirmPlan(selection:)` 读取用户选择：仅多选时按所选路径合并执行指令并重新解析步骤，否则沿用推荐路径/推荐步骤。
- `resetWorkflow()` / `editPlan()` / `cancelPlan()` 与计划检测处都对 `selectedPathIndexes` 做归零清理，保证跨工作流零残留。

### 3.4 完成勾颜色

- `WorkflowStepsList` 的 `.done` 状态由绿色改为蓝色勾，符合「完成一项自动打蓝色勾」的诉求。

---

## 四、多路径多选交互（C12 联动）

当模型输出多路径计划（`## PATH N:` 标记，`MultiPathPlanner` 解析）时，确认面板在步骤列表上方渲染 **路径选择卡片**：

- 每张卡片显示路径序号、标题、风险徽章（低/中/高）与选择依据。
- 推荐路径在 `onAppear` 时默认预选；可取消 / 改选。
- 支持多选；确认按钮在多选时显示数量「确认执行（N）」。
- 所选路径正文合并后作为执行指令，步骤追踪器从合并后的所选路径重新解析，使**用户的选择真正驱动执行**。
- 空选择（全部取消）语义回退为"使用推荐路径"，UI 层安全。

---

## 五、总开关兼容性验证

| 检查项 | 结论 |
|--------|------|
| 面板 / 胶囊渲染前置 | 均以 `vm.deepModeEnabled` 为前提，外加 `planGateState == .awaitingApproval` / `workflowPhase` 判定 |
| 关闭开关清理 | `deepModeDidDisableCleanup()` 置 `planGateState = .idle` 并 `resetWorkflow()`，阶段/步骤/多选全部归零 → 组件即刻卸载、零残留 |
| 多路径解析边界 | `MultiPathPlanner` 仅在 `if deepModeEnabled` 的计划门检测内被调用 |
| 跨会话上下文保存 | `confirmPlan` 内 C14 保存同样受 `deepModeEnabled` 保护 |

---

## 六、改动文件清单

| 文件 | 改动 |
|------|------|
| `src/ios/Agent/Chat/PlanGate.swift` | `awaitingApproval` 状态新增 `paths: [CandidatePath]` 与 `recommendedIndex` 关联值 |
| `src/ios/Agent/Chat/AIChatViewModel.swift` | 新增 `@Published selectedPathIndexes`；`confirmPlan(selection:)` 支持多选合并执行；计划检测处透传多路径与推荐序号；各清理点归零多选状态 |
| `src/ios/Views/Chat/DeepModeBanners.swift` | 新增 `FloatingWorkflowCapsule` 与 `FloatingConfirmPanel`；`DeepModeWorkflowBanner` 收敛为仅承载澄清与子代理卡片 |
| `src/ios/Views/Chat/WorkflowProgressView.swift` | `.done` 勾改为蓝色 |
| `src/ios/Views/Chat/AIChatView.swift` | 宿主以 `.overlay(.topTrailing)` / `.overlay(.bottom)` 挂载胶囊与确认面板，并经 binding 回写用户选择 |

> ⚠️ 按双端同步铁律，本功能的 Android 端对等实现（悬浮面板 + 多选）在下一小版本补齐。

---

## 七、待办与后续建议

- [ ] Android 端对等实现（悬浮面板 + 多选 + 蓝色勾）。
- [ ] 真机回归：多路径任务、纯计划、纯选择三种内容类型的生命周期。
- [ ] 进度胶囊在窄屏 / 分屏下的自适应宽度验证。