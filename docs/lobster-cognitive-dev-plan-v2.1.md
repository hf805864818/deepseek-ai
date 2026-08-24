# 深度龙虾Ai 元认知与自适应思维能力开发方案

> 在 1-5 阶段路线图基础上扩展阶段 4.5 / 5.5 —— 补齐"像人一样思考"的 14 项认知能力（P0/P1 档已合入）

| 版本 | 日期 | 总开关控制 |
|------|------|------------|
| **v2.0 (P0 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |
| **v2.1 (P1 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 |

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
| 已完成 | 9 | 层 A/B/C + 阶段 1/2/3，全部合入 main 分支 |
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
| **4.5** | **元认知与自适应思维** | **心跳自检 + 认知负荷监控 + 三层意图 + 反向验证 + 多路径 + 第一性原理 + 动态自主性 + 按需思考 + 联网进攻 + 风险预判** | **本方案新增** |
| 5 | 子智能体编排 | `Subagent` + `Task` 派发工具 | 待开发 |
| **5.5** | **自我进化与跨模式** | **任务后复盘 + 错误根因策略更新 + 失败三次换方法 + 跨模式上下文共享** | **本方案新增** |

```
阶段1(强制式Workflow) → 阶段2(反思纠错+反问) → 阶段3(规则作用域+结构化记忆)
  → 阶段4(扩充技能包) → 阶段4.5(元认知与自适应思维) [新]
  → 阶段5(子智能体编排) → 阶段5.5(自我进化与跨模式) [新]
```

> 绿色=已完成，蓝色=原路线图待开发，橙色=本方案新增

---

## 三、新增元认知能力分析：6 维度 14 项

以下 6 大维度 14 项能力，是对 TRAE Agent 2.0 官方博客 [1]、社区 Meta-Skill 协议 [2]、架构分析 [3] 以及 TRAE Agent 论文 [4] 的综合提炼，与龙虾Ai 现有 1-5 阶段的对比关系标注于每项能力中。

### 维度一：元认知——"思考自己的思考"

这是 TRAE 社区 Meta-Skill 协议揭示的最深层能力。TRAE Agent 2.0 的核心转变不是"加了更多技能"，而是模型获得了"对自己思维过程的元层级监控" [1]。龙虾Ai 的 1-5 阶段路线图完全没有触及这一层。

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

这是与龙虾Ai 最根本的哲学分歧。TRAE Agent 2.0 **主动移除了固定的 Proposal 规划阶段**，让模型"根据会话的演进状态，自主决定何时收集更多上下文、何时推理、何时行动" [1]。而龙虾Ai 的阶段 1 恰恰是反方向——用 `WorkflowPhase` 状态机强制走 idle→planning→executing→verifying。

TRAE 的判断是：刚性前置规划有时会把模型引向错误路径，尤其当需要更多代码上下文才能形成更好策略时 [3]。**与阶段 1 方向相反**，需在状态机上增加"动态退出口"。

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

TRAE 社区协议的核心原则："我的能力上限不是训练数据截止时的知识量，而是 训练知识 + 实时联网补充 + 信源仲裁 + 沙箱验证。遇到信息缺口，第一反应是联网查，不是硬撑。" [2] 龙虾Ai 有浏览器和 shell 工具，但缺少"检测到自己不确定→主动去查而不是猜测"的认知触发机制。协议定义了全环节联网触发规则：意图解码阶段遇到不熟悉的领域→立即查；代码跑不通→立即查报错原因；对自己的答案没把握→联网交叉验证。**全新能力**（有工具缺触发机制）。

**13. 主动风险预判**

不等用户说，先想到问题。用户没提到的风险，替他想到 [2]。龙虾Ai 的 `ClarifyGate` 是"有歧义先问"，但不做"这个方案可能有以下风险，我提前提示你"的主动预判。**全新能力**。

### 维度六：跨模式无缝——"切换不丢上下文"

**14. 统一跨模式上下文**

TRAE Agent 2.0：记忆在 Chat / Builder / 自定义智能体之间完全共享。可以在 Chat 里收集背景或澄清任务，切到 Builder 做完整代码生成，再把结果传给自定义智能体做高级精修——所有工具使用、提示词和响应在模式切换间持久可见 [1]。龙虾Ai 的阶段 3 提到"为未来跨模式共享打底"，但目前记忆仍是会话级的，没有"跨模式无缝切换"的机制。**阶段 3 提到但未实现**。

---

## 四、扩展阶段定义：4.5 + 5.5

本方案在原 1-5 阶段之间插入两个新阶段，不改变原阶段编号与定义。**阶段 4.5** 位于阶段 4（技能扩充）与阶段 5（子智能体编排）之间，聚焦"怎么想得更像人"；**阶段 5.5** 位于阶段 5 之后，聚焦"怎么从经验中自我进化"。之所以插在 5 之后而非 5 之前，是因为自我进化的"错误→根因→策略更新"闭环需要子智能体编排的独立上下文能力作为前提。

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
| C9 | 认知负荷实时监控 | 元认知 | 需模型自评+客户端解析 | P2 |
| C10 | 动态自主性退出口 | 自适应 | 状态机加灵活出口 | P2 |
| C11 | 按需顺序思考工具 | 自适应 | 新增 `SequentialThinkingTool` | P2 |
| C12 | 多路径并行思考 | 对抗思维 | 多次生成+比较选优 | P2 |

### 阶段 5.5：自我进化与跨模式

| 编号 | 能力 | 维度 | 实现路径 | 优先级 |
|------|------|------|----------|--------|
| C13 | 错误→根因→策略更新闭环 | 自我进化 | 自动更新规则文件（需阶段 5 子智能体支持） | P2 |
| C14 | 统一跨模式上下文 | 跨模式 | 架构级改造（记忆持久化+跨会话共享） | P2 |

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

> **P0 档验证方法**：关闭 `deepModeEnabled` → `deepModeFragment` 不注入 → 提示词中无任何自检/反向验证/风险预判指令 → 行为与原版完全一致。无状态残留、无 UI 残留。

#### P0 完成实录（v2.0 合入）

截至 2026-08-24，P0 档 5 项能力已全部实现并审查通过。以下是每项能力的实际落地详情：

| 编号 | 能力 | 改动文件 | 实现方式 | 总开关守卫位置 |
|------|------|----------|----------|----------------|
| C1 | 三层意图解码 | `AIChatViewModel.swift` L2685 | 在 `deepModeFragment` 末尾追加 "1. THREE-LAYER INTENT" 指令段，要求模型在执行前静默解码三层意图 | L5322 `if deepModeEnabled` |
| C2 | 反向验证 | `AIChatViewModel.swift` L2687 | 在 `deepModeFragment` 追加 "2. ADVERSARIAL SELF-CHECK" 指令段，要求模型主动寻找能推翻自身结论的证据 | L5322 `if deepModeEnabled` |
| C3 | 第一性原理推导 | `AIChatViewModel.swift` L2689 | 在 `deepModeFragment` 追加 "3. FIRST PRINCIPLES" 指令段，禁止依赖"上次能行"的捷径思维 | L5322 `if deepModeEnabled` |
| C4 | 主动风险预判 | `AIChatViewModel.swift` L2691 | 在 `deepModeFragment` 追加 "4. PROACTIVE RISK FORESIGHT" 指令段，要求主动提示副作用/破坏性变更/性能/安全风险 | L5322 `if deepModeEnabled` |
| C5 | 失败三次换方法 | `AIChatViewModel.swift` L1363-L1388 | 在 `maybeAutoContinueGoal` 的 `goalRunnerRoundsLeft == 0` 分支注入 fail-switch 用户消息，提示模型切换策略 | L1292 `guard deepModeEnabled` |

##### 总开关回退验证（四条边界全覆盖）

**运行时行为**：C1-C4 的提示词指令存在于 `deepModeFragment` 变量内，该变量仅在 `if deepModeEnabled`（L5322）为真时追加到系统提示词；关闭时 `deepModeFragment` 整段不注入，5 条指令全部消失。C5 的 fail-switch 注入在 `maybeAutoContinueGoal` 内，该函数首行 `guard deepModeEnabled`（L1292），关闭时直接 return，fail-switch 分支不可达。

**持久化状态**：C1-C4 为纯提示词，无状态写入。C5 注入的 fail-switch 消息是普通 `AgentMessage`，作为历史记录持久化（与深度模式开启时已有的续跑消息机制一致），不写入规则文件或结构化记忆。

**既有代码**：C1-C4 仅在 `deepModeFragment` 内追加字符串拼接，未修改任何原版函数体。C5 仅在 `goalRunnerRoundsLeft == 0` 分支内插入新逻辑，该分支原版仅做 `finishWorkflow()` + return，现新增 fail-switch 消息注入后再执行同样的 `finishWorkflow()` + return，行为兼容。

**界面 UI**：P0 档无任何 UI 新增。C5 注入的消息作为普通用户消息出现在对话流中，无特殊 UI 渲染。

##### 遗漏问题审查结论

逐项审查后确认以下三点无遗漏：

1. **总开关覆盖性**：C1-C4 受 `deepModeFragment` 外层 `if deepModeEnabled` 控制；C5 受 `maybeAutoContinueGoal` 入口 `guard deepModeEnabled` 控制。两者均无绕过路径。
2. **持久化消息残留**：C5 的 fail-switch 消息在关闭深度模式后仍作为历史记录存在于数据库，但不影响行为——关闭深度模式后 `maybeAutoContinueGoal` 不可达，不会再次注入此类消息，已有的历史消息仅作为对话记录展示，不触发任何后续逻辑。
3. **字符串插值一致性**：C5 使用 `let fci = agentHistory.count` 模式确保追加消息后正确绑定 `dbMessageId`，与已有的续跑消息处理（synthetic continue message）保持一致的代码风格。

### P1 档：客户端逻辑（3 项，改主循环计数器与钩子） ✅ 已合入

这 3 项需要在 `runAgentLoop` 里加计数器和条件注入，但不改状态机主结构、不新增独立文件。

| 编号 | 能力 | 实现方式 | 改动文件 |
|------|------|----------|----------|
| C6 | 心跳自检协议 | 在 `runAgentLoop` 中新增 `heartbeatToolCallCount` 计数器，每 5 次工具调用注入一段自检指令（"原始目标是什么？当前第几步？是否偏离？"），模型回复后继续执行 | `AIChatViewModel.swift` 主循环 |
| C7 | 任务后复盘 | 在 `WorkflowPhase` 回到 `idle` 时，新增复盘钩子：注入"请对本次任务做快速复盘（意图准确性/难度评估/工具选择/边界声明）"，模型输出写入 `StructuredMemoryStore` | `AIChatViewModel.swift` + `StructuredMemoryStore.swift` |
| C8 | 联网查询进攻 | 在 `send()` 入口新增不确定检测：模型输出中检测"我不确定/可能/大概"等不确定标记词，命中后追加"请使用联网工具查证此信息"指令 | `AIChatViewModel.swift` 输出检测 |

> **P1 档验证方法**：关闭 `deepModeEnabled` → `toolCallCount` 不触发自检注入 → 复盘钩子不执行 → 不确定检测不激活 → 主循环行为与原版完全一致。计数器值仅在 deepMode 下存在，关闭后不持久化。

#### P1 完成实录（v2.1 合入）

截至 2026-08-24，P1 档 3 项能力已全部实现并审查通过。以下是每项能力的实际落地详情：

| 编号 | 能力 | 改动文件 | 实现方式 | 总开关守卫位置 |
|------|------|----------|----------|----------------|
| C6 | 心跳自检协议 | `AIChatViewModel.swift` L5624+L6615 | 在 `runAgentLoop` 的 `loopLabel: while` 循环前新增 `heartbeatToolCallCount` 局部变量，每次有工具调用的迭代后自增 1，每 5 次在 `toolResultParts` 追加一段 `<system-reminder>` 自检指令 | `if deepModeEnabled` 包裹计数和注入 |
| C7 | 任务后复盘 | `AIChatViewModel.swift` L1276+L2727 | 在 `scheduleWorkflowFinish()` 的延迟 Task 中，`resetWorkflow()` 之后调用 `maybeRunRetrospective()`：注入复盘提示词→调用 `runAgentLoop()`→将模型回复保存到 `StructuredMemoryStore`（category=.project, source="auto:deep-mode-c7"） | `guard deepModeEnabled` 在 `scheduleWorkflowFinish` Task + `maybeRunRetrospective` 入口 |
| C8 | 联网查询进攻 | `AIChatViewModel.swift` L768+L5350+L6154+L6439+L6609 | 新增 `didInjectUncertaintyCheckThisRun` 标志位 + `detectUncertainty(in:)` 静态函数，在 `assistantText` 解析后扫描不确定标记词（中英双语），命中后在工具结果消息或独立用户消息中追加联网查证指令，每轮最多注入 1 次 | `if deepModeEnabled` 包裹检测和标志位设置 |

##### 总开关回退验证（四条边界全覆盖）

**运行时行为**：C6 的计数和注入在 `if deepModeEnabled` 块内，关闭时计数器不递增、不注入自检文本。C7 的 `maybeRunRetrospective()` 入口 `guard deepModeEnabled` 直接 return，`scheduleWorkflowFinish()` 的 Task 也检查 `self.deepModeEnabled` 后才执行。C8 的检测在 `if deepModeEnabled` 块内，关闭时 `shouldInjectUncertaintyCheck` 恒为 false，两个注入路径（工具结果追加 / 独立用户消息）均不可达。

**持久化状态**：C6 的 `heartbeatToolCallCount` 是 `runAgentLoop` 的局部变量，函数返回即销毁，不持久化。C7 的复盘提示词和模型回复作为普通 `AgentMessage` 持久化到对话历史（与 P0 C5 的 fail-switch 消息一致），`StructuredMemoryStore.add()` 仅在 `maybeRunRetrospective()` 内调用，受 `guard deepModeEnabled` 控制。C8 的 `didInjectUncertaintyCheckThisRun` 是内存标志位，不持久化。

**既有代码**：C6 在 `let toolResultMessage = ...` 之前插入新的 `if` 块，不修改原有代码。C7 在 `scheduleWorkflowFinish()` 的 Task 体内 `self.resetWorkflow()` 之后追加一行 `await self.maybeRunRetrospective()`，`maybeRunRetrospective()` 是全新方法。C8 在 `toolEntries` 赋值后插入新的检测块，在 `break` 前插入新的 `if shouldInjectUncertaintyCheck` 块，在工具结果区追加新的 `if shouldInjectUncertaintyCheck` 块——均为新增代码，不修改原有逻辑分支。

**界面 UI**：P1 档无任何 UI 新增。C6 的自检文本作为 `toolResultParts` 的一部分，不在 UI 中单独渲染。C7 的复盘提示词和模型回复作为普通对话消息出现在对话流中。C8 的查证指令作为 `<system-reminder>` 文本追加到工具结果或独立用户消息，无特殊 UI 渲染。

##### 遗漏问题审查结论

逐项审查后确认以下三点无遗漏：

1. **总开关覆盖性**：C6 的计数器递增和注入均在 `if deepModeEnabled` 内；C7 受 `scheduleWorkflowFinish` Task 的 `guard self.deepModeEnabled` 和 `maybeRunRetrospective` 入口的 `guard deepModeEnabled` 双重控制；C8 的检测、标志位设置和两个注入路径均以 `shouldInjectUncertaintyCheck` 为前提，该变量仅在 `if deepModeEnabled` 内被设为 true。三者均无绕过路径。
2. **标志位重置**：`retrospectiveHasRun` 在 `beginExecution()`（新工作流开始时）和 `deepModeDidDisableCleanup()`（总开关关闭时）重置；`didInjectUncertaintyCheckThisRun` 在 `runAgentLoop()` 入口和 `deepModeDidDisableCleanup()` 重置。重置路径完整。
3. **循环安全性**：C6 的计数器是局部变量，不影响循环退出条件（`turnCount < maxAgentTurns`）。C7 的 `maybeRunRetrospective` 调用 `runAgentLoop()` 后，模型回复的 `<<GOAL_STATE>>` sentinel 不会触发额外续跑（此时 `workflowPhase == .idle`，`maybeAutoContinueGoal` 会安全 no-op）。C8 的 `continue` 路径受 `didInjectUncertaintyCheckThisRun` 限制为每轮最多 1 次，不会导致无限循环。

### P2 档：架构级（6 项，状态机改造/多次生成/架构重构）

这 6 项涉及状态机改造、多次生成成本、或架构级重构。建议在 P0/P1 全部落地验证后再推进。

| 编号 | 能力 | 实现方式 | 改动范围 |
|------|------|----------|----------|
| C9 | 认知负荷实时监控 | 模型在每次工具调用前自评当前并行分支数、思路连贯度、新信息频率，输出结构化哨兵 `<<COGNITIVE_LOAD: branchCount=X,coherence=Y,novelty=Z>>`，客户端解析后在 UI 显示警告 | 系统提示词+哨兵解析+UI |
| C10 | 动态自主性退出口 | 在 `WorkflowPhase.planning` 增加退出口：当模型在 planning 阶段输出 `<<NEED_MORE_CONTEXT>>` 哨兵时，允许跳出 planning 去执行工具收集信息，收集完毕回到 planning | `WorkflowPhase.swift` 状态机 |
| C11 | 按需顺序思考工具 | 新增 `SequentialThinkingTool`，模型在觉得需要结构化思考时主动调用，工具内部提供"分步推理→假设检验→结论收敛"的框架 | 新增工具文件 |
| C12 | 多路径并行思考 | 在 PlanGate 阶段并行生成 3 条候选计划，客户端做去重+择优，选择最优路径进入 executing | `PlanGate.swift` + 并行调用逻辑 |
| C13 | 错误→根因→策略更新闭环 | VerifyGate 判定 failed 后，触发根因分析：注入"请分析本次失败的根本原因，并生成一条可复用的规避规则"，输出写入 `deep-rules.md` 自动追加段落 | `VerifyGate.swift` + 规则文件写入 |
| C14 | 统一跨模式上下文 | 将 `StructuredMemoryStore` 从会话级提升为 App 级持久化，所有模式共享同一记忆实例，切换模式时不丢失上下文 | 记忆层架构改造 |

> **P2 档验证方法**：每项能力均须独立验证：关闭 `deepModeEnabled` → 哨兵不解析 → 状态机退出口不激活 → 并行生成不触发 → 规则文件不被自动追加 → 记忆层不受影响 → 行为与原版完全一致。

---

## 六、总开关控制规则

所有阶段、所有新钩子，无一例外纳入 `deepModeEnabled` 单一总开关控制。这是从 v2.5 起就确立的硬约束，本方案继承并强化。

**规则 1 — 单一总开关**：所有 14 项新能力的激活条件首检项均为 `deepModeEnabled == true`。任何能力在总开关关闭时不得以任何形式（提示词注入、计数器触发、钩子执行、哨兵解析、规则写入）激活。

**规则 2 — 零残留回退**：关闭总开关时，必须 100% 回到原有功能与状态，不遗留任何行为、状态或 UI 差异。具体包括：
- **运行时行为**（不注入提示词、不触发自检、不追加复盘、不解析哨兵）
- **持久化状态**（不写入规则文件、不写入结构化记忆、计数器不持久化）
- **既有代码**（不修改原版逻辑分支，仅插入 guard）
- **界面 UI**（不显示认知负荷警告、不显示自检进度、不显示退出口提示）

**规则 3 — 插入式实现**：所有新能力均为"新增文件 + guard 注入"模式，绝不改写原有逻辑。每个新能力在代码入口处先检查 `guard deepModeEnabled else { return originalBehavior }`，确保关闭时不走新逻辑分支。

**规则 4 — 独立验证**：每项能力合入前，必须单独执行"总开关关闭→行为比对"测试，确认关闭后行为与上一个版本完全一致。测试用例覆盖：提示词内容、状态机流转、文件写入、UI 渲染四条验证路径。

### 四条不可破坏的边界

**运行时行为**：关闭时 `deepModeFragment` 为空字符串，`runAgentLoop` 中无自检注入，`VerifyGate` 验证提示词为原版，`GoalRunner` 续跑逻辑为原版 3 轮停止。

**持久化状态**：关闭时不向 `deep-rules.md` 追加任何段落，不向 `StructuredMemoryStore` 写入复盘记录，`toolCallCount` 不持久化。

**既有代码**：所有改动均为新增文件或 guard 插入，原版函数体不被修改。新增文件清单：`CognitiveHeartbeat.swift`（C6）、`RetrospectiveHook.swift`（C7）、`UncertaintyDetector.swift`（C8）、`SequentialThinkingTool.swift`（C11）、`MultiPathPlanner.swift`（C12）、`ErrorRootCauseAnalyzer.swift`（C13）。

**界面 UI**：关闭时不渲染认知负荷警告横幅、不渲染自检进度条、不渲染动态退出口提示气泡。所有 UI 元素都有 `guard deepModeEnabled` 前置检查。

---

## 七、实施路线图甘特图

按 P0→P1→P2 的优先级顺序串行推进。**P0 档已在 v2.0 中一次性合入全部 5 项**，P1 档每项独立合入，P2 档在阶段 4/5 完成后按需推进。

| 优先级 | 能力数量 | 实施方式 | 状态 |
|--------|----------|----------|------|
| P0 | 5 项 | 纯提示词注入，一个版本一次性合入 | ✅ 已完成 |
| P1 | 3 项 | 客户端逻辑，每项独立合入 | ✅ 已完成 |
| P2 | 6 项 | 架构级，阶段 4/5 完成后按需推进 | 待开发 |

---

## 八、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 提示词膨胀 | P0 档 5 项指令全部注入 `deepModeFragment`，可能导致系统提示词过长，挤占上下文窗口 | 每项指令控制在 50 token 以内，5 项合计不超过 250 token；监控 `contextManager` 的压缩触发频率 |
| 心跳自检打断节奏 | C6 每 5 次工具调用注入自检，可能打断长链工具调用的节奏 | 将自检设计为"软注入"——仅在模型自然回复轮次注入，不在工具调用中间打断；用户可在设置中调整间隔（5/10/15 次） |
| 自动规则写入冲突 | C13 自动向 `deep-rules.md` 追加规则，可能与用户手动维护的规则冲突 | 自动写入的规则加 `auto_generated: true` frontmatter 标记，与用户规则物理分隔；用户可在 UI 中一键删除所有自动生成规则 |
| 多路径生成成本 | C12 并行生成 3 条候选计划，Token 消耗 3 倍 | 仅在 PlanGate 阶段触发，且仅对复杂任务（判断依据：步骤数 ≥ 5）触发；简单任务走单路径 |
| 总开关回退不彻底 | 某项能力在关闭总开关后仍残留行为（如计数器值未被清除） | 每项合入前执行"总开关 ON→OFF→行为比对"自动化测试，四条边界全覆盖 |

---

## 参考来源

1. **TRAE, Product Thought: TRAE Agent 2.0 — From Proposal-Driven to Adaptive Reasoning.** 官方博客阐述 Agent 2.0 移除固定 Proposal 阶段、动态自主性、跨模式上下文共享等核心转变。
   https://www.trae.ai/blog/product_thought_0617

2. **TRAE 社区, Meta-Skill Protocol: Heartbeat / Cognitive Load / Adversarial Thinking / Self-Evolution.** 社区实践的元认知协议，定义心跳自检、认知负荷监控、三层意图解码、反向验证、多路径、第一性原理、失败三次换方法、联网进攻、风险预判、任务后复盘等能力。
   https://forum.trae.cn/t/topic/17326

3. **FanLv, TRAE Architecture Analysis: Harness Engineering & Agent Loop.** 架构层面分析 TRAE 如何在自主性和清晰度之间取得平衡，以及动态退出口设计。
   https://www.fanlv.fun/2026/01/18/trea-arch/

4. **TRAE Agent, arXiv:2507.23370.** TRAE Agent 的 test-time scaling 方法论，并行生成多个候选补丁→去重/回归测试分层剪枝→选优。
   https://arxiv.org/pdf/2507.23370

5. **社区实践, TRAE Agent 自我进化闭环：错误→根因→策略更新.** 详述执行偏差自动检索历史记忆→分析出错原因→优化执行规则→更新 SKILL 配置的完整链路。
   https://post.m.smzdm.com/p/a3m67kg7/

---

> 深度龙虾Ai 元认知与自适应思维能力开发方案 v2.1 (P0/P1 已完成) · 2026-08-24 · deepModeEnabled 总开关控制
