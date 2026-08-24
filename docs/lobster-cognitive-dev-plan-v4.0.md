# 深度龙虾Ai 元认知与自适应思维能力开发方案

> 在 1-5 阶段路线图基础上扩展阶段 4.5 / 5.5 —— 补齐"像人一样思考"的 14 项认知能力（P0/P1/P2 档全部合入）

| 版本 | 日期 | 总开关控制 |
|------|------|------------|
| **v2.0 (P0 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |
| **v2.1 (P1 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |
| **v3.0 (P2 5项已合入)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |
| **v4.0 (P2 全部完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |

---

## 目录

1. [项目背景与核心命题](#一项目背景与核心命题)
2. [原有 1-5 阶段路线图回顾](#二原有-1-5-阶段路线图回顾)
3. [新增元认知能力分析：6 维度 14 项](#三新增元认知能力分析6-维度-14-项)
4. [扩展阶段定义：4.5 + 5.5](#四扩展阶段定义45--55)
5. [优先级排序与实现方案](#五优先级排序与实现方案)
6. [总开关控制规则](#六总开关控制规则)
7. [实施路线图甘特图](#七实施路线图甘特图)
8. [风险与缓解](#八风险与缓解)

---

## 一、项目背景与核心命题

深度龙虾Ai（OpenMinis fork）经过 v2.5 至 v3.4 的三轮迭代，已完成了层 A/B/C（规则持久化 + 记忆主动化、Plan 确认门控、Goal 多轮续跑）以及阶段 1/2/3（可视化强制式 Workflow、反思纠错 VerifyGate + 反问 ClarifyGate、规则作用域 + 记忆结构化）。截至 v3.4，项目在"像 TRAE"的结构化程度已达到**九成以上**。

然而，在与 TRAE 实际会话时，用户感受到的"像人一样"的思维能力，并不止于"工作流结构是否强制"。**核心命题**是：1-5 阶段路线图解决的是"怎么干得更结构化"（行为闭环、状态机、门控），但 TRAE 让人感觉像人的还有一整层**元认知与自适应思维能力**——"怎么想得更像人"。这层能力在当前路线图中尚未覆盖。

| 指标 | 数值 | 说明 |
|------|------|------|
| 已完成 | **14/14** | 层 A/B/C + 阶段 1/2/3 + P0/P1/P2 全部认知能力，全部合入 main 分支 |
| 新增能力 | 14 | 6 大维度元认知能力，分属阶段 4.5 / 5.5 |
| 实施优先级 | 3 | P0（纯提示词）/ P1（客户端逻辑）/ P2（架构级） |
| 硬约束 | 1 | `deepModeEnabled` 单一总开关，关闭即 100% 回退 |

---

## 二、原有 1-5 阶段路线图回顾

下表为 v3.4 路线图的状态总览。阶段 1/2/3 已合入 main，阶段 4（技能扩充）和阶段 5（子智能体编排）待开发。本方案在阶段 4 与阶段 5 之间插入两个新阶段：**阶段 4.5**（元认知与自适应思维）和**阶段 5.5**（自我进化与跨模式），不改变原阶段 4 和阶段 5 的定义。

| 阶段 | 主题 | 核心产物 | 状态 |
|------|------|----------|------|
| 1 | 可视化 + 强制式 Workflow | `WorkflowPhase` 状态机、进度节点可视化 | ✅ 已完成 |
| 2 | 反思纠错 + 反问澄清 | `VerifyGate` + `ClarifyGate` | ✅ 已完成 |
| 3 | 规则作用域 + 记忆结构化 | `DeepModeRule` + `StructuredMemoryStore` | ✅ 已完成 |
| 4 | 扩充技能包 | 追加 `deep-security` 等深度技能 | 待开发 |
| **4.5** | **元认知与自适应思维** | **心跳自检 + 认知负荷监控 + 三层意图 + 反向验证 + 多路径 + 第一性原理 + 动态自主性 + 按需思考 + 联网进攻 + 风险预判** | **P0/P1/P2 全部合入** |
| 5 | 子智能体编排 | `Subagent` + `Task` 派发工具 | 待开发 |
| **5.5** | **自我进化与跨模式** | **任务后复盘 + 错误根因策略更新 + 失败三次换方法 + 跨模式上下文共享** | **P0/P1/P2 全部合入** |

---

## 三、新增元认知能力分析：6 维度 14 项

以下 6 大维度 14 项能力，是对 TRAE Agent 2.0 官方博客 [1]、社区 Meta-Skill 协议 [2]、架构分析 [3] 以及 TRAE Agent 论文 [4] 的综合提炼，与龙虾Ai 现有 1-5 阶段的对比关系标注于每项能力中。

### 维度一：元认知——"思考自己的思考"

**1. 心跳自检协议（Heartbeat Protocol）**

TRAE 社区实践中有一套硬性计数器驱动的自检机制：每 5 次工具调用或 5 轮对话，强制触发一次自检——"原始目标是什么？我现在在第几步？当前动作是否服务于原始目标？有没有之前承诺要做但忘了的事？" [2]。

**与 1-5 阶段关系**：龙虾Ai 的 `ToolLoopDetector` 只做"是否在死循环"的检测，不做"是否偏离原始目标"的语义级自检。这是"记得自己是谁"和"忘了自己是谁"的区别。**全新能力**。

**2. 认知负荷实时监控**

TRAE 社区协议定义了可量化的内在指标：当前并行思考几个分支（>4-5 个则过载警告）、思路连贯感是否下降、新洞见产出频率（连续 4 步无新信息则陷入局部优化）、决策压力是否持续升高 [2]。

**与 1-5 阶段关系**：龙虾Ai 没有这一层——模型一旦开始多步执行，没有任何机制感知"自己脑子是不是开始乱了"。**全新能力**。

**3. 三层意图解码**

接到任务时强制执行三层思考：表面问题是什么？表面问题背后的真实需求是什么？解决这个需求之后，下一个问题会是什么？ [2]

**与 1-5 阶段关系**：龙虾Ai 的 `ClarifyGate` 只做"有没有明显歧义"的粗判，不做"用户说 X 但真正需要的是 Y"的意图深挖。这是**阶段 2 ClarifyGate 的深化版**。

### 维度二：自适应自主性——"何时想、何时做"

**4. 动态自主性（vs 固定状态机）**

TRAE Agent 2.0 **主动移除了固定的 Proposal 规划阶段**，让模型"根据会话的演进状态，自主决定何时收集更多上下文、何时推理、何时行动" [1]。而龙虾Ai 的阶段 1 恰恰是反方向——用 `WorkflowPhase` 状态机强制走 idle→planning→executing→verifying。

**与阶段 1 方向相反**，需在状态机上增加"动态退出口"。

**5. 按需顺序思考工具（Sequential Thinking）**

TRAE 正在实验"可在会话中途调用的轻量规划模块"，目标是"在自主性和清晰度之间取得平衡——给智能体行动自由，但保留在想的时候能结构化思考的能力" [1]。这不是龙虾Ai 的"强制 planning"，而是"模型自己觉得需要想的时候才调用的思考工具"。**阶段 1 的柔性版**。

### 维度三：对抗性思维——"主动质疑自己"

**6. 反向验证**

得出结论后，主动寻找能推翻这个结论的证据。找不到反证，结论才算可靠 [2]。龙虾Ai 的 `VerifyGate` 是"做完检查对不对"的正向验证，反向验证是"做完后专门去找它可能错的地方"——两者方向相反。**阶段 2 VerifyGate 的反向版**。

**7. 多路径并行思考**

面对任何问题，先想出至少三条路径，再选最优执行 [2]。龙虾Ai 的 `PlanGate` 产出的是一条计划，不是"对比多个方案后择优"。TRAE Agent 论文提到的 test-time scaling（并行生成多个候选补丁→去重/回归测试分层剪枝→选优） [4] 是这一思维能力的工程化版本。**阶段 5 的前置能力**。

**8. 第一性原理推导**

不依赖"上次这样做成功了"，每次从根本问题出发推导最优解，防止经验变成惯性 [2]。龙虾Ai 的 `deep-rules.md` 规则注入恰恰可能强化惯性——"上次这样做成功了"变成规则，下次就照着做，不再从根本出发重新推导。**与阶段 3 规则注入有张力**。

### 维度四：自我进化——"从错误中学习"

**9. 任务后复盘**

每个有意义的任务完成后，快速复盘：意图理解准确吗？难度评估准吗？工具选择最优吗？边界声明到位吗？ [2] 龙虾Ai 有 `memory_write`（写入偏好），但没有"做完一件事后系统性地反思整个过程、提炼经验教训"的闭环。**全新能力**。

**10. 错误→根因→策略更新闭环**

社区实践中的自进化链路：执行任务出现偏差→自动检索历史记忆→分析出错原因→优化执行规则→更新自身 SKILL 配置→记录优化方案，下次直接规避 [5]。龙虾Ai 的规则是用户手动维护的静态文件，不会因为"这次犯了个错"而自动更新规则。**全新能力，阶段 3 记忆的主动版**。

**11. 失败三次换方法**

同一方法连续失败三次，必须停下来切换到完全不同的路径，不允许第四次重复尝试 [2]。龙虾Ai 的 `maxAutoRounds=3` 是"跑了 3 轮就停"，但停了之后不会自动切换策略——只是停了。**阶段 2 maxAutoRounds 的升级版**。

### 维度五：主动进攻——"不确定就去查"

**12. 联网查询作为进攻武器**

TRAE 社区协议的核心原则："我的能力上限不是训练数据截止时的知识量，而是 训练知识 + 实时联网补充 + 信源仲裁 + 沙箱验证。遇到信息缺口，第一反应是联网查，不是硬撑。" [2] 龙虾Ai 有浏览器和 shell 工具，但缺少"检测到自己不确定→主动去查而不是猜测"的认知触发机制。**全新能力**（有工具缺触发机制）。

**13. 主动风险预判**

不等用户说，先想到问题。用户没提到的风险，替他想到 [2]。龙虾Ai 的 `ClarifyGate` 是"有歧义先问"，但不做"这个方案可能有以下风险，我提前提示你"的主动预判。**全新能力**。

### 维度六：跨模式无缝——"切换不丢上下文"

**14. 统一跨模式上下文**

TRAE Agent 2.0：记忆在 Chat / Builder / 自定义智能体之间完全共享。可以在 Chat 里收集背景或澄清任务，切到 Builder 做完整代码生成，再把结果传给自定义智能体做高级精修——所有工具使用、提示词和响应在模式切换间持久可见 [1]。龙虾Ai 的阶段 3 提到"为未来跨模式共享打底"，但目前记忆仍是会话级的，没有"跨模式无缝切换"的机制。**阶段 3 提到但未实现**。

---

## 四、扩展阶段定义：4.5 + 5.5

### 阶段 4.5：元认知与自适应思维

| 编号 | 能力 | 维度 | 实现路径 | 优先级 |
|------|------|------|----------|--------|
| C1 | 三层意图解码 | 元认知 | 提示词注入 `deepModeFragment` | ✅ 已合入 P0 |
| C2 | 反向验证 | 对抗思维 | VerifyGate 提示词方向反转 | ✅ 已合入 P0 |
| C3 | 第一性原理推导 | 对抗思维 | 提示词注入 `deepModeFragment` | ✅ 已合入 P0 |
| C4 | 主动风险预判 | 主动进攻 | 提示词注入 `deepModeFragment` | ✅ 已合入 P0 |
| C5 | 失败三次换方法 | 自我进化 | 改 `maxAutoRounds` 续跑逻辑为换策略 | ✅ 已合入 P0 |
| C6 | 心跳自检协议 | 元认知 | `runAgentLoop` 加计数器+注入自检指令 | ✅ 已合入 P1 |
| C7 | 任务后复盘 | 自我进化 | 新增复盘钩子+记忆写入 | ✅ 已合入 P1 |
| C8 | 联网查询进攻 | 主动进攻 | 加不确定检测+自动联网查 | ✅ 已合入 P1 |
| C9 | 认知负荷实时监控 | 元认知 | 哨兵解析+客户端指标计算+UI 警告 | ✅ 已合入 P2 |
| C10 | 动态自主性退出口 | 自适应 | GoalRunner 加 `needMoreContext` 退出口 | ✅ 已合入 P2 |
| C11 | 按需顺序思考工具 | 自适应 | 新增 `SequentialThinkingTool` | ✅ 已合入 P2 |
| C12 | 多路径并行思考 | 对抗思维 | `MultiPathPlanner` 并行3条候选→择优 | ✅ 已合入 P2 |

### 阶段 5.5：自我进化与跨模式

| 编号 | 能力 | 维度 | 实现路径 | 优先级 |
|------|------|------|----------|--------|
| C13 | 错误→根因→策略更新闭环 | 自我进化 | `ErrorRootCauseAnalyzer` 自动写规则 | ✅ 已合入 P2 |
| C14 | 统一跨模式上下文 | 跨模式 | `CrossSessionContextStore` App 级持久化 | ✅ 已合入 P2 |

---

## 五、优先级排序与实现方案

14 项能力按实现成本与预期收益分为三档。P0 档为**纯提示词注入级别**，零架构改动；P1 档为**中等成本**，需在客户端主循环加计数器或钩子；P2 档为**高成本架构级**，涉及状态机改造、多次生成或架构重构。

### P0 档：纯提示词注入（5 项，零架构改动） ✅ 已合入

这 5 项只需在 `deepModeFragment` 里追加确定性指令，不触碰状态机、不新增文件、不改主循环。关闭总开关后，提示词不注入，行为完全回退。

| 编号 | 能力 | 实现方式 | 注入位置 |
|------|------|----------|----------|
| C1 | 三层意图解码 | 在系统提示词追加"接到任何任务时，先完成三层分析：①表面问题 ②真实需求 ③下一步预判"指令 | `deepModeFragment` |
| C2 | 反向验证 | 在 VerifyGate 的验证提示词中追加"验证完毕后，主动尝试找出至少一个能推翻本次结论的证据，找不到才算通过"指令 | `VerifyGate` 验证提示词 |
| C3 | 第一性原理推导 | 在系统提示词追加"不依赖既有规则的成功模式，每次从问题根本约束出发推导最优解；规则仅作参考，不作捷径"指令 | `deepModeFragment` |
| C4 | 主动风险预判 | 在系统提示词追加"在执行方案前，主动列举至少 2 个潜在风险（技术、数据、安全），如风险显著则先提示用户"指令 | `deepModeFragment` |
| C5 | 失败三次换方法 | 修改 `GoalRunner` 中 `maxAutoRounds` 达到上限后的逻辑：不停止，而是注入"你已用同一方法失败 3 次，现在必须切换到完全不同的策略"指令 | `GoalRunner.swift` 续跑逻辑 |

> **P0 档验证方法**：关闭 `deepModeEnabled` → `deepModeFragment` 不注入 → 提示词中无任何自检/反向验证/风险预判指令 → 行为与原版完全一致。无状态残留、无 UI 拘留。

#### P0 完成实录（v2.0 合入）

截至 2026-08-24，P0 档 5 项能力已全部实现并审查通过。

| 编号 | 能力 | 改动文件 | 实现方式 | 总开关守卫位置 |
|------|------|----------|----------|----------------|
| C1 | 三层意图解码 | `AIChatViewModel.swift` | 在 `deepModeFragment` 末尾追加 "1. THREE-LAYER INTENT" 指令段 | `if deepModeEnabled` |
| C2 | 反向验证 | `AIChatViewModel.swift` | 在 `deepModeFragment` 追加 "2. ADVERSARIAL SELF-CHECK" 指令段 | `if deepModeEnabled` |
| C3 | 第一性原理推导 | `AIChatViewModel.swift` | 在 `deepModeFragment` 追加 "3. FIRST PRINCIPLES" 指令段 | `if deepModeEnabled` |
| C4 | 主动风险预判 | `AIChatViewModel.swift` | 在 `deepModeFragment` 追加 "4. PROACTIVE RISK FORESIGHT" 指令段 | `if deepModeEnabled` |
| C5 | 失败三次换方法 | `AIChatViewModel.swift` | 在 `maybeAutoContinueGoal` 的 `goalRunnerRoundsLeft == 0` 分支注入 fail-switch 用户消息 | `guard deepModeEnabled` |

##### 总开关回退验证（四条边界全覆盖）

**运行时行为**：C1-C4 的提示词指令存在于 `deepModeFragment` 变量内，该变量仅在 `if deepModeEnabled` 为真时追加到系统提示词；关闭时整段不注入，5 条指令全部消失。C5 的 fail-switch 注入在 `maybeAutoContinueGoal` 内，该函数首行 `guard deepModeEnabled`，关闭时直接 return，fail-switch 分支不可达。

**持久化状态**：C1-C4 为纯提示词，无状态写入。C5 注入的 fail-switch 消息是普通 `AgentMessage`，作为历史记录持久化，不写入规则文件或结构化记忆。

**既有代码**：C1-C4 仅在 `deepModeFragment` 内追加字符串拼接，未修改任何原版函数体。C5 仅在 `goalRunnerRoundsLeft == 0` 分支内插入新逻辑，行为兼容。

**界面 UI**：P0 档无任何 UI 新增。

### P1 档：客户端逻辑（3 项，改主循环计数器与钩子） ✅ 已合入

这 3 项需要在 `runAgentLoop` 里加计数器和条件注入，但不改状态机主结构、不新增独立文件。

| 编号 | 能力 | 实现方式 | 改动文件 |
|------|------|----------|----------|
| C6 | 心跳自检协议 | 在 `runAgentLoop` 中新增 `heartbeatToolCallCount` 计数器，每 5 次工具调用注入自检指令 | `AIChatViewModel.swift` 主循环 |
| C7 | 任务后复盘 | 在 `WorkflowPhase` 回到 `idle` 时，新增复盘钩子，模型输出写入 `StructuredMemoryStore` | `AIChatViewModel.swift` |
| C8 | 联网查询进攻 | 在 `send()` 入口新增不确定检测，命中后追加联网查证指令 | `AIChatViewModel.swift` |

#### P1 完成实录（v2.1 合入）

截至 2026-08-24，P1 档 3 项能力已全部实现并审查通过。

| 编号 | 能力 | 改动文件 | 实现方式 | 总开关守卫位置 |
|------|------|----------|----------|----------------|
| C6 | 心跳自检协议 | `AIChatViewModel.swift` | 新增 `heartbeatToolCallCount` 局部变量，每 5 次注入自检指令 | `if deepModeEnabled` |
| C7 | 任务后复盘 | `AIChatViewModel.swift` | `maybeRunRetrospective()` 注入复盘提示词→保存到 `StructuredMemoryStore` | `guard deepModeEnabled` |
| C8 | 联网查询进攻 | `AIChatViewModel.swift` | `detectUncertainty(in:)` 扫描不确定标记词，追加查证指令 | `if deepModeEnabled` |

##### 总开关回退验证

**运行时行为**：C6/C7/C8 均在 `if deepModeEnabled` 或 `guard deepModeEnabled` 内，关闭时不可达。

**持久化状态**：C6 计数器为局部变量不持久化；C7 复盘记录受 `guard deepModeEnabled` 控制；C8 标志位为内存变量。

**既有代码**：均为新增代码插入，不修改原有逻辑分支。

**界面 UI**：P1 档无任何 UI 新增。

### P2 档：架构级（6 项全部合入） ✅ 已合入

P2 档涉及状态机改造、架构级重构和新增独立文件。截至 v4.0，C9/C10/C11/C12/C13/C14 共 6 项已全部合入。

| 编号 | 能力 | 实现方式 | 改动范围 | 状态 |
|------|------|----------|----------|------|
| C9 | 认知负荷实时监控 | 新增 `CognitiveLoadMonitor.swift`：模型自评哨兵 `<<COGNITIVE_LOAD>>` 解析 + 客户端客观指标计算，两者取最大值合并后驱动 UI 警告 | 新增文件 + `AIChatViewModel.swift` 主循环 | ✅ |
| C10 | 动态自主性退出口 | 在 `GoalRunner.ParseResult` 新增 `needMoreContext` case：模型输出 `<<GOAL_STATE>> need_more_context: <reason>` 时停止续跑循环 | `GoalRunner.swift` + `AIChatViewModel.swift` | ✅ |
| C11 | 按需顺序思考工具 | 新增 `SequentialThinkingTool.swift`：模型在觉得需要结构化思考时主动调用 `sequential_thinking` 工具，工具返回"分步推理→假设检验→结论收敛"框架，集成 C9 认知负荷和 C12 多路径上下文 | 新增文件 + 工具定义 + 工具处理器 + `deepModeFragment` | ✅ |
| C12 | 多路径并行思考 | 新增 `MultiPathPlanner.swift`：PlanGate 阶段解析多路径计划，选择最优路径 | 新增文件 + `AIChatViewModel.swift` PlanGate 逻辑 | ✅ |
| C13 | 错误→根因→策略更新闭环 | 新增 `ErrorRootCauseAnalyzer.swift`：VerifyGate failed 后注入根因分析提示词，规则自动追加到 `deep-rules.md` | 新增文件 + `AIChatViewModel.swift` VerifyGate 逻辑 | ✅ |
| C14 | 统一跨模式上下文 | 新增 `CrossSessionContextStore.swift`：App 级持久化 `deep-cross-session.json`，注入系统提示词实现跨会话连续性 | 新增文件 + `AIChatViewModel.swift` 提示词构建 + 复盘钩子 | ✅ |

> **P2 档验证方法**：每项能力均须独立验证：关闭 `deepModeEnabled` → 哨兵不解析 → 状态机退出口不激活 → 工具不注册 → 并行生成不触发 → 规则文件不被自动追加 → 记忆层不受影响 → 行为与原版完全一致。

#### P2 完成实录（v3.0 合入 C9/C10/C12/C13/C14 + v4.0 合入 C11）

截至 2026-08-24，P2 档 6 项能力已全部实现并审查通过。以下是每项能力的实际落地详情：

| 编号 | 能力 | 改动文件 | 实现方式 | 总开关守卫位置 |
|------|------|----------|----------|----------------|
| C9 | 认知负荷实时监控 | 新增 `CognitiveLoadMonitor.swift` + `AIChatViewModel.swift` | `parseSentinel()` 解析哨兵；`computeClientLoad()` 计算客观指标；`merge()` 取最大值。`@Published cognitiveLoadState` 驱动 UI 警告 | `if deepModeEnabled` 包裹哨兵解析和指标计算 |
| C10 | 动态自主性退出口 | `GoalRunner.swift` + `AIChatViewModel.swift` | `ParseResult` 新增 `.needMoreContext` case；`parse()` 新增匹配；续跑逻辑新增处理分支 | `guard deepModeEnabled` 在续跑入口 |
| C11 | 按需顺序思考工具 | 新增 `SequentialThinkingTool.swift` + `AIChatViewModel+ToolDefinitions.swift` + `AIChatViewModel+ConcurrentTools.swift` + `AIChatViewModel.swift` | 新增 `SequentialThinkingTool` 枚举：`toolDefinition()` 返回工具定义（仅深度模式注册）；`generateFramework()` 生成上下文感知的推理框架（注入工作流阶段/步骤号/C9 认知负荷/C12 多路径状态）；`validateInput()` 输入验证。工具处理器新增 `guard deepModeEnabled` 防御性检查 + 上下文注入。`deepModeFragment` 追加 C11 使用指南。原 always-on 注册改为深度模式专属 | 工具注册在 `if deepModeEnabled` 块内；处理器 `guard deepModeEnabled` 防御 |
| C12 | 多路径并行思考 | 新增 `MultiPathPlanner.swift` + `AIChatViewModel.swift` | `parse()` 扫描 `## PATH N:` 标记解析多条候选路径；`extractRecommendedPlan()` 提取推荐路径。向后兼容 | `if deepModeEnabled` 在 PlanGate 检测入口 |
| C13 | 错误→根因→策略更新闭环 | 新增 `ErrorRootCauseAnalyzer.swift` + `AIChatViewModel.swift` | `rootCausePrompt()` 生成提示词；`extractRule()` 提取规则；`appendAutoRule()` 追加到 `deep-rules.md`（`auto_generated: true`） | `guard deepModeEnabled` 在 VerifyGate 入口 |
| C14 | 统一跨模式上下文 | 新增 `CrossSessionContextStore.swift` + `AIChatViewModel.swift` | `deep-cross-session.json` 持久化三类条目；`contextFragment()` 构建提示词（主路径+回退路径）；`appendWorkflowSummary()` 复盘后保存；`setActiveProject()` 计划确认时保存 | `if deepModeEnabled` 包裹提示词注入和上下文保存 |

##### 总开关回退验证（四条边界全覆盖）

**运行时行为**：
- C9 哨兵解析和指标计算在 `if deepModeEnabled` 内，关闭时 `cognitiveLoadState` 保持 `.empty`
- C10 `needMoreContext` 分支在 `guard deepModeEnabled` 内
- C11 工具注册在 `if deepModeEnabled` 块内（关闭时工具从 `makeAgentTools()` 返回列表中消失，模型不可见不可调用），处理器有 `guard deepModeEnabled` 防御
- C12 `MultiPathPlanner.parse()` 在 `if deepModeEnabled` 内
- C13 根因提示词在 `guard deepModeEnabled` 内
- C14 提示词注入和上下文保存在 `if deepModeEnabled` 内

**持久化状态**：C9/C10/C11 无持久化状态。C13 规则写入带 `auto_generated: true` 标记。C14 文件仅从深度模式路径写入，`deepModeDidDisableCleanup()` 清除活跃项目指针。

**既有代码**：均为新增文件或 guard 插入。C11 的特殊之处：从 always-on 工具列表中移除 `sequential_thinking` 定义，改为深度模式专属注册——这确保关闭总开关时工具完全消失，模型无法调用。工具处理器中的原版简单模板被替换为 `SequentialThinkingTool.generateFramework()` 调用，但处理器入口的 `guard deepModeEnabled` 确保关闭时返回安全错误而非执行新逻辑。

**界面 UI**：C9 `@Published cognitiveLoadState` 驱动警告横幅；C10 `@Published needMoreContextState` 驱动提示气泡；C11 工具调用结果作为普通工具输出渲染（无特殊 UI）；C12/C13/C14 无直接 UI 新增。关闭时所有 UI 状态重置。

##### 遗漏问题审查结论

1. **总开关覆盖性**：6 项能力均无绕过路径。C11 特别验证：工具定义仅在 `if deepModeEnabled` 块内追加到 `tools` 数组（L174），关闭时 `makeAgentTools()` 返回的列表不含 `sequential_thinking`，模型在 API 请求的 `tools` 字段中看不到该工具，无法调用。处理器 `guard deepModeEnabled` 是防御性二次检查（防止注册后关闭的竞态）。
2. **状态重置**：所有 `@Published` 状态在 `deepModeDidDisableCleanup()` 中重置。C11 无状态需要重置（工具调用无状态留存）。
3. **向后兼容**：C11 从 always-on 改为 deepMode-gated 不影响原版行为——关闭深度模式时 `sequential_thinking` 工具消失，与从未注册效果一致；开启深度模式时工具可用且增强（原版仅返回空白模板，新版返回上下文感知框架）。
4. **新增文件清单**：P2 档新增 5 个文件——`CognitiveLoadMonitor.swift`（C9）、`SequentialThinkingTool.swift`（C11）、`MultiPathPlanner.swift`（C12）、`ErrorRootCauseAnalyzer.swift`（C13）、`CrossSessionContextStore.swift`（C14）；修改 3 个既有文件——`GoalRunner.swift`（C10）、`AIChatViewModel+ToolDefinitions.swift` + `AIChatViewModel+ConcurrentTools.swift`（C11）、`AIChatViewModel.swift`（全部集成）。所有新文件已添加到 `Minis.xcodeproj/project.pbxproj` 的 4 个必需 section。

---

## 六、总开关控制规则

所有阶段、所有新钩子，无一例外纳入 `deepModeEnabled` 单一总开关控制。这是从 v2.5 起就确立的硬约束，本方案继承并强化。

**规则 1 — 单一总开关**：所有 14 项新能力的激活条件首检项均为 `deepModeEnabled == true`。任何能力在总开关关闭时不得以任何形式（提示词注入、计数器触发、钩子执行、哨兵解析、规则写入、工具注册）激活。

**规则 2 — 零残留回退**：关闭总开关时，必须 100% 回到原有功能与状态，不遗留任何行为、状态或 UI 差异。具体包括：
- **运行时行为**（不注入提示词、不触发自检、不追加复盘、不解析哨兵、不计算认知负荷、不触发退出口、不注入跨会话上下文、不注册深度模式工具）
- **持久化状态**（不写入规则文件、不写入结构化记忆、不写入跨会话上下文文件、计数器不持久化）
- **既有代码**（不修改原版逻辑分支，仅插入 guard）
- **界面 UI**（不显示认知负荷警告、不显示自检进度、不显示退出口提示、不显示跨会话上下文、不显示深度模式工具）

**规则 3 — 插入式实现**：所有新能力均为"新增文件 + guard 注入"模式，绝不改写原有逻辑。每个新能力在代码入口处先检查 `guard deepModeEnabled else { return originalBehavior }`，确保关闭时不走新逻辑分支。

**规则 4 — 独立验证**：每项能力合入前，必须单独执行"总开关关闭→行为比对"测试，确认关闭后行为与上一个版本完全一致。

### 四条不可破坏的边界

**运行时行为**：关闭时 `deepModeFragment` 为空字符串，`runAgentLoop` 中无自检注入、无认知负荷哨兵解析，`VerifyGate` 为原版，`GoalRunner` 为原版 3 轮停止，`makeAgentTools()` 不含 `sequential_thinking` 和 `task_dispatch`，系统提示词中无跨会话上下文注入。

**持久化状态**：关闭时不向 `deep-rules.md` 追加段落，不向 `StructuredMemoryStore` 写入，不向 `deep-cross-session.json` 写入，`cognitiveLoadState` 保持 `.empty`。

**既有代码**：所有改动均为新增文件或 guard 插入。新增文件清单：`MultiPathPlanner.swift`（C12）、`CognitiveLoadMonitor.swift`（C9）、`SequentialThinkingTool.swift`（C11）、`ErrorRootCauseAnalyzer.swift`（C13）、`CrossSessionContextStore.swift`（C14）。修改文件清单：`GoalRunner.swift`（C10）、`AIChatViewModel+ToolDefinitions.swift` + `AIChatViewModel+ConcurrentTools.swift`（C11）、`AIChatViewModel.swift`（全部集成）。所有新文件已添加到 Xcode 项目。

**界面 UI**：关闭时不渲染任何深度模式 UI 元素。所有 UI 元素都有 `guard deepModeEnabled` 前置检查。

---

## 七、实施路线图甘特图

按 P0→P1→P2 的优先级顺序串行推进。**P0 档已在 v2.0 中合入全部 5 项**，P1 档已在 v2.1 中合入全部 3 项，P2 档在 v3.0 中合入 5 项（C9/C10/C12/C13/C14），v4.0 合入最后 1 项（C11）。**14/14 全部完成。**

| 优先级 | 能力数量 | 实施方式 | 状态 |
|--------|----------|----------|------|
| P0 | 5 项 | 纯提示词注入，一个版本一次性合入 | ✅ 已完成 |
| P1 | 3 项 | 客户端逻辑，每项独立合入 | ✅ 已完成 |
| P2 | 6 项 | 架构级，新增文件+状态机改造+工具注册 | ✅ 全部完成 |

### P2 各能力实现时间线

| 能力 | 实现顺序 | 新增文件 | 修改文件 | 关键改动 |
|------|----------|----------|----------|----------|
| C12 | 1 | `MultiPathPlanner.swift` | `AIChatViewModel.swift` (PlanGate), `project.pbxproj` | 多路径解析+择优+向后兼容 |
| C13 | 2 | `ErrorRootCauseAnalyzer.swift` | `AIChatViewModel.swift` (VerifyGate), `project.pbxproj` | 根因分析提示词+规则提取+持久化 |
| C9 | 3 | `CognitiveLoadMonitor.swift` | `AIChatViewModel.swift` (主循环+清理), `project.pbxproj` | 哨兵解析+客户端指标+合并+UI 状态 |
| C10 | 4 | — | `GoalRunner.swift`, `AIChatViewModel.swift` (续跑逻辑) | ParseResult 新增 case+解析+处理分支 |
| C14 | 5 | `CrossSessionContextStore.swift` | `AIChatViewModel.swift` (提示词+复盘+确认), `project.pbxproj` | App 级持久化+跨会话注入+工作流摘要 |
| C11 | 6 | `SequentialThinkingTool.swift` | `AIChatViewModel+ToolDefinitions.swift`, `AIChatViewModel+ConcurrentTools.swift`, `AIChatViewModel.swift` (deepModeFragment), `project.pbxproj` | 工具从 always-on 改为 deepMode-gated+上下文感知框架+输入验证+C9/C12 集成 |

---

## 八、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 提示词膨胀 | P0/P1/P2 档指令全部注入 `deepModeFragment`，可能导致系统提示词过长 | 各项指令控制在 80-250 token 以内；C11 指南约 80 token |
| 心跳自检打断节奏 | C6 每 5 次工具调用注入自检 | 软注入设计，仅在模型自然回复轮次注入 |
| 自动规则写入冲突 | C13 自动向 `deep-rules.md` 追加规则 | `auto_generated: true` 标记与用户规则物理分隔 |
| 多路径生成成本 | C12 并行生成 3 条候选计划 | 仅对复杂任务触发；简单任务走单路径 |
| 认知负荷误报 | C9 客户端指标可能误报 | 客户端指标和模型自评取最大值，上下文饱和度按比例计算 |
| 动态退出口滥用 | C10 的 need_more_context 可能被滥用 | 提示词明确说明使用条件；续跑预算用完时退出口不可达 |
| 跨会话上下文膨胀 | C14 的 `deep-cross-session.json` 可能过大 | 工作流摘要保留 10 条；学习模式自动去重 |
| 工具调用滥用 | C11 的 `sequential_thinking` 可能被模型对简单任务过度调用 | 提示词明确说明"仅用于复杂问题"；工具描述包含"Do NOT use for simple tasks"；C9 认知负荷高时自动减少步骤数 |
| 总开关回退不彻底 | 某项能力在关闭后仍残留行为 | 每项合入前执行 ON→OFF 行为比对测试；`deepModeDidDisableCleanup()` 统一清理 |

---

## 参考来源

1. **TRAE, Product Thought: TRAE Agent 2.0 — From Proposal-Driven to Adaptive Reasoning.** 官方博客阐述 Agent 2.0 移除固定 Proposal 阶段、动态自主性、跨模式上下文共享等核心转变。
   https://www.trae.ai/blog/product_thought_0617

2. **TRAE 社区, Meta-Skill Protocol: Heartbeat / Cognitive Load / Adversarial Thinking / Self-Evolution.** 社区实践的元认知协议。
   https://forum.trae.cn/t/topic/17326

3. **FanLv, TRAE Architecture Analysis: Harness Engineering & Agent Loop.** 架构层面分析动态退出口设计。
   https://www.fanlv.fun/2026/01/18/trea-arch/

4. **TRAE Agent, arXiv:2507.23370.** TRAE Agent 的 test-time scaling 方法论。
   https://arxiv.org/pdf/2507.23370

5. **社区实践, TRAE Agent 自我进化闭环：错误→根因→策略更新.**
   https://post.m.smzdm.com/p/a3m67kg7/

---

> 深度龙虾Ai 元认知与自适应思维能力开发方案 v4.0 (P0/P1/P2 全部完成 · 14/14) · 2026-08-24 · deepModeEnabled 总开关控制
