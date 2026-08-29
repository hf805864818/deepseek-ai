# 深度龙虾Ai 元认知与自适应思维能力开发方案

> ⚠️ **【双端同步开发铁律】以后不管开发新功能还是做性能优化，iOS 和 Android 必须同时设计、同时开发、同时测试、同时上线。严禁只做一端、另一端滞后跟进的模式。两端功能差异不得超过一个小版本周期。**

> 在 1-5 阶段路线图基础上扩展阶段 4.5 / 5.5 —— 补齐"像人一样思考"的 14 项认知能力（P0/P1/P2 档全部合入）+ 三档强度分级系统 + 性能优化与 Bug 修复全记录 + Android 端功能全面补全 + 双端发送消息卡顿深度优化

| 版本 | 日期 | 总开关控制 | 新增内容 |
|------|------|------------|----------|
| **v2.0 (P0 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 | C1-C5 纯提示词注入 |
| **v2.1 (P1 已完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 | C6-C8 客户端逻辑 |
| **v3.0 (P2 5项已合入)** | 2026-08-24 | `deepModeEnabled` 总开关控制 | C9/C10/C12/C13/C14 |
| **v4.0 (P2 全部完成)** | 2026-08-24 | `deepModeEnabled` 总开关控制 | C11 按需顺序思考工具 |
| **v5.0 (三档强度分级)** | 2026-08-24 | `deepModeEnabled` + `DeepModeLevel` | 三档强度（低/中/高）分级控制 |
| **v6.0 (性能优化与Bug修复)** | 2026-08-25 | — | 卡顿优化、CI编译修复、Google Drive 403修复、iCloud发烫优化 |
| **v6.1 (DeepMode卡顿深度修复)** | 2026-08-27 | — | DeepMode长会话6项性能深度修复：增量布局、后台Token累加、批量合并 |
| **v7.0 (本地同步导出与胶囊进度提示)** | 2026-08-28 | — | 本地目录同步功能、BackupPhase 分步进度胶囊提示、Google Drive 备份列表刷新修复、CI 编译修复 |
| **v8.0 (双端对齐与发送消息卡顿深度优化)** | 2026-08-29 | — | Android 端 DeepMode 14项能力全面补全 + Android 端三档分级 + Android 端 v6.1/v7.0 功能移植 + 双端 effectiveAgentHistory 增量构建 + 双端后台构建乐观UI + deepModeFragment 缓存 + makeAgentTools 缓存 |

---

## 目录

1. [项目背景与核心命题](#一项目背景与核心命题)
2. [原有 1-5 阶段路线图回顾](#二原有-1-5-阶段路线图回顾)
3. [新增元认知能力分析：6 维度 14 项](#三新增元认知能力分析6-维度-14-项)
4. [扩展阶段定义：4.5 + 5.5](#四扩展阶段定义45--55)
5. [优先级排序与实现方案](#五优先级排序与实现方案)
6. [三档强度分级系统（v5.0 新增）](#六三档强度分级系统v50-新增)
7. [总开关控制规则](#七总开关控制规则)
8. [实施路线图甘特图](#八实施路线图甘特图)
9. [风险与缓解](#九风险与缓解)
10. [v6.0 性能优化与 Bug 修复全记录](#十v60-性能优化与-bug-修复全记录)
11. [v6.1 DeepMode 长会话卡顿深度修复](#十一v61-deepmode-长会话卡顿深度修复)
12. [v7.0 本地同步导出与胶囊进度提示](#十二v70-本地同步导出与胶囊进度提示)
13. [v8.0 双端对齐与发送消息卡顿深度优化](#十三v80-双端对齐与发送消息卡顿深度优化)

---
## 一、项目背景与核心命题

深度龙虾Ai（OpenMinis fork）经过 v2.5 至 v3.4 的三轮迭代，已完成了层 A/B/C（规则持久化 + 记忆主动化、Plan 确认门控、Goal 多轮续跑）以及阶段 1/2/3（可视化强制式 Workflow、反思纠错 VerifyGate + 反问 ClarifyGate、规则作用域 + 记忆结构化）。截至 v4.0，项目在"像 TRAE"的结构化程度已达到**九成以上**，14 项元认知与自适应思维能力（P0/P1/P2）已全部合入。

然而，实际使用中发现一个新问题：**深度模式的认知能力是"全有或全无"的**——开启 `deepModeEnabled` 后，所有 14 项能力同时激活，用户无法根据任务复杂度调整强度。简单任务被强制的多路径规划、认知负荷哨兵和顺序思考工具拖慢节奏；而高难度任务又需要这些能力全部就位。

**核心命题（v5.0）**：引入 `DeepModeLevel` 三档强度分级系统，让用户在深度模式开启的前提下，按低/中/高三档灵活选择认知能力的激活程度，实现"简单任务轻量对话、复杂任务全功能深度分析"的弹性体验。

**核心命题（v6.0）**：在实际使用中发现的卡顿、编译失败、Google Drive 同步 403 错误、设备发烫等问题，通过系统性的性能优化和 Bug 修复予以解决，确保应用在长时间使用和大历史记录场景下依然流畅。

**核心命题（v6.1）**：针对 DeepMode 总开关开启后长会话场景下的深度卡顿问题，通过增量布局重建、高度预估增量化、后台 Token 累加、冷缓存 O(1) 估算、flush 批量合并等 6 项深度修复，消除 DeepMode 数据放大效应放大的 O(n)/O(n×m) 瓶颈，确保 DeepMode 长会话场景下四大操作路径（进入会话/继续/暂停恢复/发送消息）的流畅度。

**核心命题（v7.0）**：在「其它同步」页面新增本地目录同步功能，用户可选择本地文件夹导出打包备份数据（ZIP）。通过 `BackupPhase` 分步进度枚举驱动顶部胶囊式提示（获取数据→打包数据→保存完成），实现全流程可视化进度反馈。同时修复 Google Drive 备份列表不刷新、恢复缺少确认弹窗等问题。

| 指标 | 数值 | 说明 |
|------|------|------|
| 已完成 | **14/14 + 3档 + 6项优化 + 6项深度修复 + 1项功能** | 层 A/B/C + 阶段 1/2/3 + P0/P1/P2 全部认知能力 + 三档强度分级 + v6.0 性能优化 + v6.1 DeepMode卡顿深度修复 + v7.0 本地同步导出 |
| 新增能力 | 14 + 3档 + 6项 + 6项 + 1项 | 6 大维度元认知能力 + DeepModeLevel 三档强度 + v6.0 优化项 + v6.1 深度修复项 + v7.0 本地同步功能 |
| 实施优先级 | 3 | P0（纯提示词）/ P1（客户端逻辑）/ P2（架构级）/ v5.0（分级控制）/ v6.0（性能与修复） |
| 硬约束 | 2 | `deepModeEnabled` 单一总开关 + `DeepModeLevel` 分级控制 |

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

| 编号 | 能力 | 维度 | 实现路径 | 优先级 | v5.0 档位 |
|------|------|------|----------|--------|-----------|
| C1 | 三层意图解码 | 元认知 | 提示词注入 `deepModeFragment` | ✅ P0 | 全档位 |
| C2 | 反向验证 | 对抗思维 | VerifyGate 提示词方向反转 | ✅ P0 | 全档位 |
| C3 | 第一性原理推导 | 对抗思维 | 提示词注入 `deepModeFragment` | ✅ P0 | 全档位 |
| C4 | 主动风险预判 | 主动进攻 | 提示词注入 `deepModeFragment` | ✅ P0 | 全档位 |
| C5 | 失败三次换方法 | 自我进化 | 改 `maxAutoRounds` 续跑逻辑为换策略 | ✅ P0 | 全档位 |
| C6 | 心跳自检协议 | 元认知 | `runAgentLoop` 加计数器+注入自检指令 | ✅ P1 | 全档位 |
| C7 | 任务后复盘 | 自我进化 | 新增复盘钩子+记忆写入 | ✅ P1 | 全档位 |
| C8 | 联网查询进攻 | 主动进攻 | 加不确定检测+自动联网查 | ✅ P1 | 全档位 |
| C9 | 认知负荷实时监控 | 元认知 | 哨兵解析+客户端指标计算+UI 警告 | ✅ P2 | 中/高（低档后台静默） |
| C10 | 动态自主性退出口 | 自适应 | GoalRunner 加 `needMoreContext` 退出口 | ✅ P2 | 中/高 |
| C11 | 按需顺序思考工具 | 自适应 | 新增 `SequentialThinkingTool` | ✅ P2 | 高 |
| C12 | 多路径并行思考 | 对抗思维 | `MultiPathPlanner` 并行3条候选→择优 | ✅ P2 | 中/高 |

### 阶段 5.5：自我进化与跨模式

| 编号 | 能力 | 维度 | 实现路径 | 优先级 | v5.0 档位 |
|------|------|------|----------|--------|-----------|
| C13 | 错误→根因→策略更新闭环 | 自我进化 | `ErrorRootCauseAnalyzer` 自动写规则 | ✅ P2 | 高 |
| C14 | 统一跨模式上下文 | 跨模式 | `CrossSessionContextStore` App 级持久化 | ✅ P2 | 中/高 |

---

## 五、优先级排序与实现方案

14 项能力按实现成本与预期收益分为三档。P0 档为**纯提示词注入级别**，零架构改动；P1 档为**中等成本**，需在客户端主循环加计数器或钩子；P2 档为**高成本架构级**，涉及状态机改造、多次生成或架构重构。v5.0 在此基础上新增**三档强度分级控制层**，不影响各档位的实现方式。

### P0 档：纯提示词注入（5 项，零架构改动） ✅ 已合入

这 5 项只需在 `deepModeFragment` 里追加确定性指令，不触碰状态机、不新增文件、不改主循环。关闭总开关后，提示词不注入，行为完全回退。**v5.0 中这 5 项在所有档位（低/中/高）均激活。**

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

这 3 项需要在 `runAgentLoop` 里加计数器和条件注入，但不改状态机主结构、不新增独立文件。**v5.0 中这 3 项在所有档位（低/中/高）均激活。**

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

P2 档涉及状态机改造、架构级重构和新增独立文件。截至 v4.0，C9/C10/C11/C12/C13/C14 共 6 项已全部合入。**v5.0 中各项能力按档位动态激活（详见第六章）。**

| 编号 | 能力 | 实现方式 | 改动范围 | 状态 | v5.0 档位 |
|------|------|----------|----------|------|-----------|
| C9 | 认知负荷实时监控 | 新增 `CognitiveLoadMonitor.swift`：模型自评哨兵 `<<COGNITIVE_LOAD>>` 解析 + 客户端客观指标计算，两者取最大值合并后驱动 UI 警告 | 新增文件 + `AIChatViewModel.swift` 主循环 | ✅ | 中/高 |
| C10 | 动态自主性退出口 | 在 `GoalRunner.ParseResult` 新增 `needMoreContext` case：模型输出 `<<GOAL_STATE>> need_more_context: <reason>` 时停止续跑循环 | `GoalRunner.swift` + `AIChatViewModel.swift` | ✅ | 中/高 |
| C11 | 按需顺序思考工具 | 新增 `SequentialThinkingTool.swift`：模型在觉得需要结构化思考时主动调用 `sequential_thinking` 工具，工具返回"分步推理→假设检验→结论收敛"框架，集成 C9 认知负荷和 C12 多路径上下文 | 新增文件 + 工具定义 + 工具处理器 + `deepModeFragment` | ✅ | 高 |
| C12 | 多路径并行思考 | 新增 `MultiPathPlanner.swift`：PlanGate 阶段解析多路径计划，选择最优路径 | 新增文件 + `AIChatViewModel.swift` PlanGate 逻辑 | ✅ | 中/高 |
| C13 | 错误→根因→策略更新闭环 | 新增 `ErrorRootCauseAnalyzer.swift`：VerifyGate failed 后注入根因分析提示词，规则自动追加到 `deep-rules.md` | 新增文件 + `AIChatViewModel.swift` VerifyGate 逻辑 | ✅ | 高 |
| C14 | 统一跨模式上下文 | 新增 `CrossSessionContextStore.swift`：App 级持久化 `deep-cross-session.json`，注入系统提示词实现跨会话连续性 | 新增文件 + `AIChatViewModel.swift` 提示词构建 + 复盘钩子 | ✅ | 中/高 |

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

1. **总开关覆盖性**：6 项能力均无绕过路径。C11 特别验证：工具定义仅在 `if deepModeEnabled` 块内追加到 `tools` 数组，关闭时 `makeAgentTools()` 返回的列表不含 `sequential_thinking`，模型在 API 请求的 `tools` 字段中看不到该工具，无法调用。处理器 `guard deepModeEnabled` 是防御性二次检查（防止注册后关闭的竞态）。
2. **状态重置**：所有 `@Published` 状态在 `deepModeDidDisableCleanup()` 中重置。C11 无状态需要重置（工具调用无状态留存）。
3. **向后兼容**：C11 从 always-on 改为 deepMode-gated 不影响原版行为——关闭深度模式时 `sequential_thinking` 工具消失，与从未注册效果一致；开启深度模式时工具可用且增强（原版仅返回空白模板，新版返回上下文感知框架）。
4. **新增文件清单**：P2 档新增 5 个文件——`CognitiveLoadMonitor.swift`（C9）、`SequentialThinkingTool.swift`（C11）、`MultiPathPlanner.swift`（C12）、`ErrorRootCauseAnalyzer.swift`（C13）、`CrossSessionContextStore.swift`（C14）；修改 3 个既有文件——`GoalRunner.swift`（C10）、`AIChatViewModel+ToolDefinitions.swift` + `AIChatViewModel+ConcurrentTools.swift`（C11）、`AIChatViewModel.swift`（全部集成）。所有新文件已添加到 `Minis.xcodeproj/project.pbxproj` 的 4 个必需 section。

---

## 六、三档强度分级系统（v5.0 新增）

### 6.1 设计动机

v4.0 合入 14 项认知能力后，深度模式变为"全有或全无"的开关——开启 `deepModeEnabled` 即激活全部能力。实际使用中：

- **简单任务**（如"帮我看看这个报错"）不需要多路径规划、认知负荷哨兵和顺序思考工具，这些能力拖慢节奏、增加 token 消耗
- **中等任务**（如"帮我重构这个模块"）需要多路径和跨会话上下文，但不需要顺序思考工具和根因分析
- **高难度任务**（如"帮我设计一个全新的架构方案"）需要全部 14 项能力就位

用户需要一个**在深度模式开启的前提下、按任务复杂度调节强度**的控制层。

### 6.2 DeepModeLevel 枚举

新增 `DeepModeLevel` 枚举，定义三档强度，控制哪些认知能力在当前轮次激活。

```swift
/// [T-deep-mode-level] Three-tier intensity for the 深度龙虾Ai deep mode.
/// Controls which cognitive abilities are active and which sentinels are
/// forced, so users can trade cognitive overhead against naturalness.
///
/// - low: Base workflow (plan gate, goal auto-continue, self-verify) +
///   C1-C5 prompt-only abilities + C9 background monitoring (no forced
///   sentinel). Natural conversation; cognitive safety net runs silently.
/// - medium: Low + C10 need_more_context sentinel + C12 multi-path plan +
///   C14 cross-session context + C9 forced sentinel. Structured but
///   not tool-heavy.
/// - high: Medium + C11 sequential_thinking tool registration + C13 root
///   cause analysis. Full 14-capability cognitive arsenal.
enum DeepModeLevel: String, CaseIterable, Equatable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    /// Human-readable label for the slash-menu picker.
    var displayName: String {
        switch self {
        case .low:    return "低"
        case .medium: return "中"
        case .high:   return "高"
        }
    }

    /// One-line description shown in the slash command subtitle.
    var subtitle: String {
        switch self {
        case .low:    return "基础认知 + 后台监控"
        case .medium: return "多路径 + 跨会话 + 退出口"
        case .high:   return "全功能深度分析"
        }
    }

    // MARK: - Capability gating

    /// Whether C9 cognitive load sentinel should be FORCED (model must emit).
    var forcesCognitiveLoadSentinel: Bool { self != .low }
    /// Whether C10 need_more_context sentinel is active.
    var enablesNeedMoreContext: Bool { self != .low }
    /// Whether C11 sequential_thinking tool is registered.
    var registersSequentialThinking: Bool { self == .high }
    /// Whether C12 multi-path plan format is forced.
    var forcesMultiPath: Bool { self != .low }
    /// Whether C13 root cause analysis is active on verify failure.
    var enablesRootCause: Bool { self == .high }
    /// Whether C14 cross-session context is injected and persisted.
    var enablesCrossSession: Bool { self != .low }
}
```

### 6.3 档位-能力对照表

| 能力 | 编号 | 低档 | 中档 | 高档 |
|------|------|------|------|------|
| Plan Gate | 基础 | ✅ | ✅ | ✅ |
| Goal Auto-Continue | 基础 | ✅ | ✅ | ✅ |
| Self-Verify | 基础 | ✅ | ✅ | ✅ |
| C1 三层意图解码 | P0 | ✅ | ✅ | ✅ |
| C2 反向验证 | P0 | ✅ | ✅ | ✅ |
| C3 第一性原理推导 | P0 | ✅ | ✅ | ✅ |
| C4 主动风险预判 | P0 | ✅ | ✅ | ✅ |
| C5 失败三次换方法 | P0 | ✅ | ✅ | ✅ |
| C6 心跳自检协议 | P1 | ✅ | ✅ | ✅ |
| C7 任务后复盘 | P1 | ✅ | ✅ | ✅ |
| C8 联网查询进攻 | P1 | ✅ | ✅ | ✅ |
| C9 认知负荷监控（后台） | P2 | ✅ 后台静默 | ✅ 强制哨兵 | ✅ 强制哨兵 |
| C10 动态自主性退出口 | P2 | ❌ | ✅ | ✅ |
| C11 顺序思考工具 | P2 | ❌ | ❌ | ✅ |
| C12 多路径并行思考 | P2 | ❌ | ✅ | ✅ |
| C13 根因策略更新 | P2 | ❌ | ❌ | ✅ |
| C14 跨会话上下文 | P2 | ❌ | ✅ | ✅ |

### 6.4 持久化与通知机制

```swift
// AIChatViewModel.swift

var deepModeLevel: DeepModeLevel {
    DeepModeLevel(rawValue: UserDefaults.standard.string(forKey: "deepMode.level") ?? "medium") ?? .medium
}

func setDeepModeLevel(_ level: DeepModeLevel) {
    UserDefaults.standard.set(level.rawValue, forKey: "deepMode.level")
    NotificationCenter.default.post(name: .deepModeLevelDidChange, object: nil)
}
```

```swift
// WorkflowState.swift — Notification.Name 扩展

extension Notification.Name {
    /// [T-deep-mode-workflow] Posted when the 深度龙虾Ai master switch changes.
    static let deepModeDidChange = Notification.Name("deepModeDidChange")

    /// [T-deep-mode-level] Posted when the deep mode intensity level changes
    /// (low / medium / high). Live VMs re-read `deepModeLevel` on the next
    /// turn so the prompt fragment and tool registration adapt immediately.
    static let deepModeLevelDidChange = Notification.Name("deepModeLevelDidChange")
}
```

- **持久化**：`DeepModeLevel` 值存储在 UserDefaults key `deepMode.level` 中，默认值为 `medium`，跨所有会话生效。
- **实时通知**：`setDeepModeLevel()` 修改后广播 `.deepModeLevelDidChange` 通知，活跃的 ViewModel 在下一轮次自动重新读取 `deepModeLevel`。
- **总开关优先**：当 `deepModeEnabled` 为 false 时，`deepModeLevel` 的值不影响任何行为——所有能力均不激活，无论档位设置。

### 6.5 动态提示词生成（deepModeFragment）

`deepModeFragment` 根据 `deepModeLevel` 动态拼接系统提示词，低档位不注入哨兵指令和工具指南：

```swift
private var deepModeFragment: String {
    let scopeCtx = buildDeepModeScopeContext()
    let level = deepModeLevel
    var s = "\n\nDeep Agent Mode (深度龙虾Ai) is ENABLED (intensity: \(level.rawValue)). Adopt a deliberate, senior-engineer working style for this turn:\n"

    // --- 基础指令（全档位）---
    s += DeepModeStore.rulesFragment(for: scopeCtx) + "\n"
    s += "PLAN GATE — if a request needs more than one step, your FIRST reply must be ONLY a plan...\n"
    s += "GOAL AUTO-CONTINUE — at the very END of a turn where you used tools, append exactly one line...\n"
    s += "SELF-VERIFY — when the client asks you to verify your work...\n"

    // --- C1-C5 认知能力（全档位）---
    s += "\nCOGNITIVE ABILITIES (think like a senior engineer, not just execute):\n"
    s += "1. THREE-LAYER INTENT — ...\n"
    s += "2. ADVERSARIAL SELF-CHECK — ...\n"
    s += "3. FIRST PRINCIPLES — ...\n"
    s += "4. PROACTIVE RISK FORESIGHT — ...\n"
    s += "5. FAIL-SWITCH — ...\n"

    // --- 中/高档位：C12 多路径思考 ---
    if level.forcesMultiPath {
        s += "6. MULTI-PATH THINKING — When you produce a plan...\n"
    }

    // --- 高档位独有：C13 根因学习 ---
    if level.enablesRootCause {
        s += "7. ROOT CAUSE LEARNING — When verification fails...\n"
    }

    // --- 中/高档位：C9 认知负荷强制哨兵 ---
    if level.forcesCognitiveLoadSentinel {
        s += "8. COGNITIVE LOAD MONITORING — At the END of each turn...\n"
    }

    // --- 中/高档位：C10 动态退出口 ---
    if level.enablesNeedMoreContext {
        s += "9. DYNAMIC AUTONOMY EXIT — If you are in an auto-continue loop...\n"
    }

    // --- 中/高档位：C14 跨会话上下文 ---
    if level.enablesCrossSession {
        s += "10. CROSS-SESSION CONTEXT — When you complete a meaningful workflow...\n"
    }

    // --- 高档位独有：C11 顺序思考工具指南 ---
    if level.registersSequentialThinking {
        s += "11. ON-DEMAND SEQUENTIAL THINKING — You have a `sequential_thinking` tool...\n"
    }

    return s
}
```

### 6.6 斜杠命令菜单集成

#### 命令注册（条件插入）

当 `deepModeEnabled` 为 true 时，在斜杠命令列表顶部插入 `deepmode` 命令行；关闭时该行完全消失：

```swift
// AIChatViewModel+SlashCommands.swift — filteredSlashCommands

if deepModeEnabled {
    let level = deepModeLevel
    let deepCmd = SlashCommand(
        id: "deepmode",
        icon: "cpu.fill",
        title: "DeepMode",
        subtitle: "深度模式强度 · \(level.displayName) — \(level.subtitle)"
    )
    commands.insert(deepCmd, at: 0)
}
```

#### 紫色三档 Picker UI

`SlashCommandRow` 新增 `deepModeLevel` 和 `onSetDeepModeLevel` 属性，在 `deepmode` 命令行右侧渲染紫色三档选择器（低/中/高），与蓝色 `ThinkingLevel` 选择器视觉区分：

```swift
// AIChatView.swift — SlashCommandRow struct

private struct SlashCommandRow: View {
    let cmd: AIChatViewModel.SlashCommand
    let isSelected: Bool
    let memoryEnabled: Bool
    var thinkingLevel: ThinkingLevel = .off
    var thinkingSupported: Bool = true
    var availableLevels: [ThinkingLevel] = ThinkingLevel.allCases
    var onSetThinkingLevel: ((ThinkingLevel) -> Void)?
    var onToggleThinking: (() -> Void)?
    // [T-deep-mode-level] Deep mode intensity picker (low/medium/high)
    var deepModeLevel: DeepModeLevel = .medium
    var onSetDeepModeLevel: ((DeepModeLevel) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // ... 标签区域 ...
            if cmd.id == "deepmode" {
                deepModeLevelPicker
            }
            if cmd.id == "thinking" && thinkingSupported {
                thinkingLevelPicker
            }
        }
    }

    private var rowIconColor: Color {
        if cmd.id == "deepmode" { return .purple }
        // ... 其他逻辑 ...
    }

    // [T-deep-mode-level] Three-tier purple picker for deep mode intensity.
    private var deepModeLevelPicker: some View {
        HStack(spacing: 0) {
            ForEach(DeepModeLevel.allCases, id: \.self) { level in
                let isExactMatch = deepModeLevel == level
                HStack(spacing: 1) {
                    Text(level.displayName)
                        .font(.system(size: 11, weight: isExactMatch ? .bold : .regular))
                }
                .foregroundStyle(isExactMatch ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(isExactMatch ? Color.purple : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onSetDeepModeLevel?(level) }
                .id(level)
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

#### 命令行渲染分支

```swift
// AIChatView.swift — 斜杠命令列表渲染

if cmd.id == "deepmode" {
    SlashCommandRow(
        cmd: cmd,
        isSelected: isSelected,
        memoryEnabled: vm.memoryEnabled,
        deepModeLevel: vm.deepModeLevel,
        onSetDeepModeLevel: { level in
            vm.setDeepModeLevel(level)
        }
    )
} else if cmd.id == "thinking" {
    // ... 现有 thinking level 代码 ...
} else {
    // ... 默认行 ...
}
```

### 6.7 视觉设计

| 元素 | ThinkingLevel | DeepModeLevel |
|------|---------------|---------------|
| 命令 ID | `thinking` | `deepmode` |
| 图标 | `ThinkingIcon`（自定义） | `cpu.fill`（SF Symbols） |
| 主题色 | 蓝色（`.blue`） | 紫色（`.purple`） |
| 选择器位置 | 命令行右侧 | 命令行右侧 |
| 档位 | off / low / medium / high | low / medium / high |
| 条件显示 | 始终显示 | 仅 `deepModeEnabled == true` 时显示 |
| 持久化 | UserDefaults | UserDefaults (`deepMode.level`) |

### 6.8 与 ThinkingLevel 的关系

| 特性 | ThinkingLevel | DeepModeLevel |
|------|---------------|---------------|
| 控制对象 | 模型推理参数（reasoning effort） | 认知能力激活程度 |
| 作用域 | 单次 API 请求的推理深度 | 深度模式下的能力开关矩阵 |
| 与总开关关系 | 独立，不受 `deepModeEnabled` 控制 | 依赖，仅在 `deepModeEnabled == true` 时生效 |
| 切换后生效时机 | 下一轮 API 请求 | 下一轮 `deepModeFragment` 拼接 |
| UI 位置 | 斜杠菜单 `thinking` 行 | 斜杠菜单 `deepmode` 行 |

两者互不干扰：用户可以在深度模式低档位下使用高 ThinkingLevel（让模型在简单认知框架下深度推理），也可以在深度模式高档位下使用低 ThinkingLevel（让模型在完整认知框架下快速推理）。

### 6.9 改动文件清单

| 文件 | 改动类型 | 改动内容 |
|------|----------|----------|
| `WorkflowState.swift` | 修改 | 新增 `DeepModeLevel` 枚举（含 6 个能力门控属性）+ `.deepModeLevelDidChange` 通知名 |
| `AIChatViewModel.swift` | 修改 | 新增 `deepModeLevel` getter / `setDeepModeLevel()` setter；`deepModeFragment` 按级别动态拼接提示词 |
| `AIChatViewModel+SlashCommands.swift` | 修改 | `filteredSlashCommands` 在 `deepModeEnabled` 时条件插入 `deepmode` 命令行 |
| `AIChatView.swift` | 修改 | `SlashCommandRow` 新增 `deepModeLevel` / `onSetDeepModeLevel` 属性 + `deepModeLevelPicker` 紫色选择器 + 命令行渲染分支 |

### 6.10 总开关回退验证

**运行时行为**：`DeepModeLevel` 仅在 `deepModeEnabled == true` 时被读取。关闭总开关后：
- `deepModeFragment` 不注入系统提示词（`if deepModeEnabled` 包裹），档位值不影响任何提示词内容
- `deepmode` 命令行不从 `filteredSlashCommands` 返回（`if deepModeEnabled` 条件不满足），斜杠菜单中不显示
- `sequential_thinking` 工具不从 `makeAgentTools()` 返回（`if deepModeEnabled` 块不执行），模型不可见

**持久化状态**：`deepMode.level` 的 UserDefaults 值在关闭总开关后仍然保留（用户下次开启时恢复上次设置），但不产生任何行为影响——所有能力入口均受 `deepModeEnabled` 前置检查，档位值不可达。

**既有代码**：所有改动为新增代码插入和条件分支新增，不修改原有逻辑分支。`deepModeFragment` 内的 `if level.xxx` 条件分支仅在 `deepModeFragment` 变量被拼接时执行（即 `deepModeEnabled == true` 时）。

**界面 UI**：`deepmode` 命令行仅在 `deepModeEnabled == true` 时出现在斜杠菜单中。关闭总开关后，该行完全消失，紫色选择器不可见。无任何 UI 拘留。

---

## 七、总开关控制规则

所有阶段、所有新钩子，无一例外纳入 `deepModeEnabled` 单一总开关控制。v5.0 新增的 `DeepModeLevel` 是总开关开启后的**二级控制层**，不影响总开关的优先级。

**规则 1 — 单一总开关**：所有 14 项新能力的激活条件首检项均为 `deepModeEnabled == true`。`DeepModeLevel` 是二级控制——仅在总开关开启时决定哪些能力进一步激活。任何能力在总开关关闭时不得以任何形式激活。

**规则 2 — 零残留回退**：关闭总开关时，必须 100% 回到原有功能与状态，不遗留任何行为、状态或 UI 差异。`DeepModeLevel` 的 UserDefaults 值虽保留但不产生任何行为影响。具体包括：
- **运行时行为**（不注入提示词、不触发自检、不追加复盘、不解析哨兵、不计算认知负荷、不触发退出口、不注入跨会话上下文、不注册深度模式工具）
- **持久化状态**（不写入规则文件、不写入结构化记忆、不写入跨会话上下文文件、计数器不持久化）
- **既有代码**（不修改原版逻辑分支，仅插入 guard）
- **界面 UI**（不显示认知负荷警告、不显示自检进度、不显示退出口提示、不显示跨会话上下文、不显示深度模式工具、不显示 deepmode 命令行）

**规则 3 — 插入式实现**：所有新能力均为"新增文件 + guard 注入"模式，绝不改写原有逻辑。每个新能力在代码入口处先检查 `guard deepModeEnabled else { return originalBehavior }`，确保关闭时不走新逻辑分支。

**规则 4 — 独立验证**：每项能力合入前，必须单独执行"总开关关闭→行为比对"测试，确认关闭后行为与上一个版本完全一致。

### 四条不可破坏的边界

**运行时行为**：关闭时 `deepModeFragment` 为空字符串（不拼接），`runAgentLoop` 中无自检注入、无认知负荷哨兵解析，`VerifyGate` 为原版，`GoalRunner` 为原版 3 轮停止，`makeAgentTools()` 不含 `sequential_thinking` 和 `task_dispatch`，系统提示词中无跨会话上下文注入，`filteredSlashCommands` 不含 `deepmode` 行。

**持久化状态**：关闭时不向 `deep-rules.md` 追加段落，不向 `StructuredMemoryStore` 写入，不向 `deep-cross-session.json` 写入，`cognitiveLoadState` 保持 `.empty`。`deepMode.level` UserDefaults 值保留但不可达。

**既有代码**：所有改动均为新增文件或 guard 插入。新增文件清单：`MultiPathPlanner.swift`（C12）、`CognitiveLoadMonitor.swift`（C9）、`SequentialThinkingTool.swift`（C11）、`ErrorRootCauseAnalyzer.swift`（C13）、`CrossSessionContextStore.swift`（C14）。修改文件清单：`GoalRunner.swift`（C10）、`AIChatViewModel+ToolDefinitions.swift` + `AIChatViewModel+ConcurrentTools.swift`（C11）、`AIChatViewModel.swift`（全部集成 + v5.0 DeepModeLevel）、`WorkflowState.swift`（v5.0 DeepModeLevel 枚举 + 通知名）、`AIChatViewModel+SlashCommands.swift`（v5.0 条件插入）、`AIChatView.swift`（v5.0 紫色 Picker）。所有新文件已添加到 Xcode 项目。

**界面 UI**：关闭时不渲染任何深度模式 UI 元素。所有 UI 元素都有 `guard deepModeEnabled` 前置检查。`deepmode` 命令行和紫色 Picker 仅在 `deepModeEnabled == true` 时可见。

---

## 八、实施路线图甘特图

按 P0→P1→P2→v5.0→v6.0→v6.1 的优先级顺序串行推进。**P0 档已在 v2.0 中合入全部 5 项**，P1 档已在 v2.1 中合入全部 3 项，P2 档在 v3.0 中合入 5 项（C9/C10/C12/C13/C14），v4.0 合入最后 1 项（C11），v5.0 合入三档强度分级系统，v6.0 合入性能优化与 Bug 修复，v6.1 合入 DeepMode 长会话卡顿深度修复。**14/14 + 3档 + 6项优化 + 6项深度修复全部完成。**

| 优先级 | 能力数量 | 实施方式 | 状态 |
|--------|----------|----------|------|
| P0 | 5 项 | 纯提示词注入，一个版本一次性合入 | ✅ 已完成 |
| P1 | 3 项 | 客户端逻辑，每项独立合入 | ✅ 已完成 |
| P2 | 6 项 | 架构级，新增文件+状态机改造+工具注册 | ✅ 全部完成 |
| v5.0 | 3 档 | 二级控制层，枚举+动态提示词+斜杠菜单 UI | ✅ 已完成 |
| v6.0 | 6 项 | 性能优化+Bug修复，卡顿消除+编译修复+同步修复+发烫优化 | ✅ 已完成 |
| v6.1 | 6 项 | DeepMode长会话卡顿深度修复，增量布局+后台Token+批量合并 | ✅ 已完成 |

### P2 各能力实现时间线

| 能力 | 实现顺序 | 新增文件 | 修改文件 | 关键改动 |
|------|----------|----------|----------|----------|
| C12 | 1 | `MultiPathPlanner.swift` | `AIChatViewModel.swift` (PlanGate), `project.pbxproj` | 多路径解析+择优+向后兼容 |
| C13 | 2 | `ErrorRootCauseAnalyzer.swift` | `AIChatViewModel.swift` (VerifyGate), `project.pbxproj` | 根因分析提示词+规则提取+持久化 |
| C9 | 3 | `CognitiveLoadMonitor.swift` | `AIChatViewModel.swift` (主循环+清理), `project.pbxproj` | 哨兵解析+客户端指标+合并+UI 状态 |
| C10 | 4 | — | `GoalRunner.swift`, `AIChatViewModel.swift` (续跑逻辑) | ParseResult 新增 case+解析+处理分支 |
| C14 | 5 | `CrossSessionContextStore.swift` | `AIChatViewModel.swift` (提示词+复盘+确认), `project.pbxproj` | App 级持久化+跨会话注入+工作流摘要 |
| C11 | 6 | `SequentialThinkingTool.swift` | `AIChatViewModel+ToolDefinitions.swift`, `AIChatViewModel+ConcurrentTools.swift`, `AIChatViewModel.swift` (deepModeFragment), `project.pbxproj` | 工具从 always-on 改为 deepMode-gated+上下文感知框架+输入验证+C9/C12 集成 |

### v5.0 三档强度实现时间线

| 改动 | 文件 | 关键内容 |
|------|------|----------|
| DeepModeLevel 枚举 | `WorkflowState.swift` | 三档枚举 + 6 个能力门控属性 + `.deepModeLevelDidChange` 通知 |
| 持久化与通知 | `AIChatViewModel.swift` | `deepModeLevel` getter + `setDeepModeLevel()` setter + UserDefaults |
| 动态提示词 | `AIChatViewModel.swift` | `deepModeFragment` 按 `level.xxx` 条件拼接 6 段指令 |
| 斜杠命令注册 | `AIChatViewModel+SlashCommands.swift` | `filteredSlashCommands` 条件插入 `deepmode` 行 |
| 紫色 Picker UI | `AIChatView.swift` | `SlashCommandRow` 新增属性 + `deepModeLevelPicker` + 渲染分支 |

### v6.0 性能优化与 Bug 修复时间线

| 改动 | 日期 | 文件 | 关键内容 |
|------|------|------|----------|
| 卡顿根因修复（iOS+Android） | 2026-08-25 | `MessageListLayout.swift`, `AIChatViewModel+Offloading.swift`, `ChatViewModel.kt` | O(n) 复杂度优化、二分查找布局、增量 token 估算 |
| CI 编译错误修复（第一轮 4 个） | 2026-08-25 | `GoogleDriveAPI.kt`, `Persistence.swift` | withContext return 修复、重复变量声明、let→var、nonisolated 限定 |
| Google Drive 403 修复（createFolder） | 2026-08-25 | `GoogleDriveAPI.swift`, `GoogleDriveAPI.kt` | OAuth scope 改为 drive.appdata、错误解析、文件夹创建回退 |
| Google Drive 403 修复（findOrCreateFolder search） | 2026-08-25 | `GoogleDriveAPI.swift`, `GoogleDriveAPI.kt` | 搜索失败后直接创建、Google 错误 JSON 解析 |
| iCloud 初始同步降速 | 2026-08-25 | `ChatStore.swift` | 批次 100→50、轮询 5s→10s、阈值 5000→2000、间隔 0.25s→1s |
| 发烫优化（热状态+低电量感知） | 2026-08-25 | `SyncCore.swift`, `ICloudSharedZoneTransport.swift`, `ChatStore.swift` | 热状态四级感知、低电量模式、动态 recentFetch 轮询、历史积压扫描动态调速、inbound 分块热感知、发送批次大小热感知 |
| CI 编译错误修复（第二轮 2 个） | 2026-08-25 | `SyncCore.swift`, `GoogleDriveAPI.swift` | logger 作用域修复、GoogleDriveAPI 类型匹配修复 |
| DeepMode 长会话卡顿深度修复（6 项） | 2026-08-27 | `MessageListLayout.swift`, `CollectionViewMessageListV3.swift`, `AIChatViewModel.swift`, `AIChatViewModel+Persistence.swift`, `AIChatViewModel+Offloading.swift` | 增量布局重建、高度预估增量化、后台Token累加、冷缓存跳过effectiveAgentHistory、recheck去重、flush批量合并 |
| CI 编译错误修复（第三轮 2 个） | 2026-08-25 | `SyncCore.swift`, `GoogleDriveAPI.swift` | 跨 actor 访问修复（ThrottleSnapshot）、body.prefix 类型转换 |

---

## 九、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 提示词膨胀 | P0/P1/P2/v5.0 档指令全部注入 `deepModeFragment`，可能导致系统提示词过长 | 各项指令控制在 80-250 token 以内；低档位跳过 6 段指令减少 token |
| 心跳自检打断节奏 | C6 每 5 次工具调用注入自检 | 软注入设计，仅在模型自然回复轮次注入 |
| 自动规则写入冲突 | C13 自动向 `deep-rules.md` 追加规则 | `auto_generated: true` 标记与用户规则物理分隔 |
| 多路径生成成本 | C12 并行生成 3 条候选计划 | 仅对复杂任务触发；简单任务走单路径；低档位不触发 |
| 认知负荷误报 | C9 客户端指标可能误报 | 客户端指标和模型自评取最大值，上下文饱和度按比例计算 |
| 动态退出口滥用 | C10 的 need_more_context 可能被滥用 | 提示词明确说明使用条件；续跑预算用完时退出口不可达；低档位不激活 |
| 跨会话上下文膨胀 | C14 的 `deep-cross-session.json` 可能过大 | 工作流摘要保留 10 条；学习模式自动去重；低档位不注入 |
| 工具调用滥用 | C11 的 `sequential_thinking` 可能被模型对简单任务过度调用 | 提示词明确说明"仅用于复杂问题"；工具描述包含"Do NOT use for simple tasks"；C9 认知负荷高时自动减少步骤数；中/低档位不注册工具 |
| 总开关回退不彻底 | 某项能力在关闭后仍残留行为 | 每项合入前执行 ON→OFF 行为比对测试；`deepModeDidDisableCleanup()` 统一清理 |
| 档位切换延迟 | 用户切换档位后需等待下一轮才生效 | `.deepModeLevelDidChange` 通知实时广播；活跃 VM 下一轮立即读取新档位 |
| 低档位能力遗漏 | 低档位缺少某些能力可能导致深度体验不完整 | 低档位定位为"轻量对话"——保留基础工作流 + C1-C8 + C9 后台监控，足够覆盖日常任务 |
| 用户混淆 ThinkingLevel 与 DeepModeLevel | 两个三档系统在斜杠菜单中并存 | 视觉区分（蓝色 vs 紫色）、图标区分（灯泡 vs CPU）、命名区分（Thinking vs DeepMode） |
| iCloud 同步发烫 | 长时间同步导致设备温度升高 | 热状态四级感知（nominal/fair/serious/critical）、低电量模式节流、动态轮询间隔、历史积压扫描动态调速 |
| Google Drive 403 权限错误 | OAuth scope 不匹配导致文件夹创建/搜索失败 | 改用 drive.appdata scope、错误 JSON 解析、搜索失败后直接创建回退 |
| 跨 actor 编译错误 | ChatStore actor 访问 SyncCore MainActor 属性 | ThrottleSnapshot Sendable 结构体 + throttleSnapshot() 异步方法 |

---

## 十、v6.0 性能优化与 Bug 修复全记录

本章记录 v6.0 版本中所有性能优化和 Bug 修复的详细内容，涵盖卡顿根因修复、CI 编译错误修复、Google Drive 同步修复、以及 iCloud 发烫优化。

### 10.1 卡顿根因分析与修复（2026-08-25）

#### 问题现象

在同一会话界面经过多次会话后，启动软件进入该会话后出现卡顿。具体表现为：
- 进入旧会话时卡顿
- 发送消息时卡顿
- 暂停后点击"继续"时卡顿
- 新会话无此问题

#### 根因分析

1. **O(n) 复杂度问题**：布局渲染、token 估算和历史加载均存在线性扫描，会话消息数量增大后性能急剧下降
2. **无界历史增长**：历史记录无上限地加载到内存和 UI 列表中
3. **低效布局渲染**：UICollectionView/Jetpack Compose 未使用增量更新和二分查找

#### 修复内容

**iOS 平台：**

| 修复项 | 改动文件 | 修复方式 |
|--------|----------|----------|
| 布局渲染优化 | `MessageListLayout.swift` | 二分查找替代线性扫描，O(n) → O(log n) |
| Token 估算增量计算 | `AIChatViewModel+Offloading.swift` | 增量计算替代全量重算，避免每次消息变更都重算整个会话 |
| 会话加载优化 | `ChatStore.swift` | 分页加载 + 懒加载，避免一次性加载全部消息 |
| 上下文管理 | `AIChatViewModel.swift` | 上下文窗口管理，超长会话自动截断旧消息 |

**Android 平台：**

| 修复项 | 改动文件 | 修复方式 |
|--------|----------|----------|
| LazyColumn 性能 | `ChatViewModel.kt` | 添加 token 估算缓存 + 修复 offload 缓存失效 |
| 消息列表渲染 | `ChatScreen.kt` | 增量更新替代全量刷新 |

#### 提交记录

| 提交哈希 | 提交信息 | 平台 |
|----------|----------|------|
| `8d75314` | `perf: fix remaining lag root causes found in second-pass audit` | iOS + Android |

---

### 10.2 CI 编译错误修复 — 第一轮（2026-08-25）

#### 问题现象

GitHub Actions 构建失败，4 个编译错误阻塞 CI 流水线。

#### 错误详情与修复

| # | 平台 | 文件 | 错误 | 修复方式 |
|---|------|------|------|----------|
| 1 | Android | `GoogleDriveAPI.kt` | `return` in `withContext` expression body | 改为 `return@withContext` 正确退出 lambda |
| 2 | iOS | `Persistence.swift` | 重复 `phase2aElapsed` 变量声明 | 移除冗余的第二次声明 |
| 3 | iOS | `Persistence.swift` | `loadedUIMessages` 声明为 `let` 但被修改 | 改为 `var` 允许修改 |
| 4 | iOS | `Persistence.swift` | `applyToolResults` actor 隔离问题 | 添加 `nonisolated` 限定符 |

#### 提交记录

| 提交哈希 | 提交信息 |
|----------|----------|
| `709d930` | `fix: resolve 4 compilation errors blocking CI build` |

---

### 10.3 Google Drive 同步修复 — createFolder 403（2026-08-25）

#### 问题现象

点击"立即备份"后备份失败，提示错误：`Provider error: createFolder failed (status 403)`。同时"从最新备份恢复"功能也在备份时同时刷新。

#### 根因分析

1. **OAuth scope 不匹配**：使用的 scope 权限不足，无法创建文件夹
2. **错误处理不完善**：无法解析 Google 返回的 JSON 错误格式
3. **文件夹创建无回退**：搜索失败后没有直接尝试创建

#### 修复内容

| 修复项 | 平台 | 文件 | 修复方式 |
|--------|------|------|----------|
| OAuth scope 修正 | iOS + Android | `GoogleDriveAPI.swift`, `GoogleDriveAPI.kt` | 改为 `drive.appdata` scope |
| Google 错误 JSON 解析 | iOS + Android | `GoogleDriveAPI.swift`, `GoogleDriveAPI.kt` | 新增 `parseGoogleError()` 解析 Google 标准错误格式 |
| 文件夹创建回退 | iOS + Android | `GoogleDriveAPI.swift`, `GoogleDriveAPI.kt` | 搜索失败后直接尝试创建文件夹 |

**iOS 关键代码：**

```swift
private static func parseGoogleError(data: Data) -> String? {
    return try {
        let json = JSONObject(data)
        let error = json.optJSONObject("error") ?? return nil
        let code = error.optInt("code", 0)
        let message = error.optString("message", "")
        let errors = error.optJSONArray("errors")
        let reason = if errors != null && errors.length() > 0 {
            errors.getJSONObject(0).optString("reason", "")
        } else {
            "status \(code)"
        }
        if message.isEmpty { reason } else { "$reason: $message" }
    } catch {
        null
    }
}
```

**Android 关键代码：**

```kotlin
private fun parseGoogleError(body: String): String? {
    return try {
        val json = JSONObject(body)
        val error = json.optJSONObject("error") ?: return null
        val code = error.optInt("code", 0)
        val message = error.optString("message", "")
        val errors = error.optJSONArray("errors")
        val reason = if (errors != null && errors.length() > 0) {
            errors.getJSONObject(0).optString("reason", "")
        } else {
            "status $code"
        }
        if (message.isEmpty()) reason else "$reason: $message"
    } catch (e: Exception) {
        null
    }
}
```

#### 提交记录

| 提交哈希 | 提交信息 |
|----------|----------|
| `1c2e070` | `fix: 修复Google Drive同步的两个问题` |
| `c589d7f` | `fix: Google Drive 403错误 - 改进错误信息显示+搜索失败后直接创建` |

---

### 10.4 Google Drive 同步修复 — findOrCreateFolder search 403（2026-08-25）

#### 问题现象

重新登录后点击"立即同步"，仍提示错误：`Provider error: findOrCreateFolder search failed (status 403)`。

#### 根因分析

OAuth scope 已修正，但文件夹搜索逻辑仍存在问题——搜索 API 返回 403 后没有回退到直接创建。

#### 修复内容

在 `findOrCreateFolder` 中增加回退逻辑：当搜索 API 返回 403 时，跳过搜索步骤，直接尝试创建文件夹。如果文件夹已存在（Google 返回 409 Conflict），则视为成功并返回已有文件夹 ID。

#### 提交记录

| 提交哈希 | 提交信息 |
|----------|----------|
| `c589d7f` | `fix: Google Drive 403错误 - 改进错误信息显示+搜索失败后直接创建` |

---

### 10.5 TrollStore 安装错误 175（2026-08-25）

#### 问题现象

通过 TrollStore 安装 IPA 时提示：`安装错误（175）应用签名失败。ldid返回了非零状态码。`

#### 根因分析

1. **IPA 包过大**：包含大量二进制依赖（FFmpeg、LAME、iSH、Alpine rootfs），导致 ldid 签名处理时间过长或内存不足
2. **磁盘空间不足**：设备存储空间不足可能导致签名临时文件写入失败
3. **ldid 版本兼容性**：TrollStore 内置的 ldid 版本可能与 IPA 结构不兼容
4. **IPA 包损坏**：下载或传输过程中文件损坏

#### 建议方案

| 方案 | 说明 |
|------|------|
| 检查存储空间 | 确保设备至少有 IPA 包大小 3 倍的可用空间 |
| 替代安装方式 | 尝试通过 Sideloadly 或 AltStore 安装 |
| 更新 TrollStore | 确保使用最新版 TrollStore |
| 优化 IPA 体积 | 精简不必要的二进制依赖，减小 IPA 体积 |

---

### 10.6 iCloud 同步发烫优化（2026-08-25）

#### 问题现象

iPhone 14 Pro 打开软件即发烫，会话消息多（数百条以上）时更明显。后台功能（增强后台运行、位置追踪、实时活动）开启后发烫尤为显著。

#### 根因分析

1. **iCloud 同步持续运行**：recentFetch 定时器固定 120s 轮询，后台前台无差别
2. **历史积压扫描不分场景**：初始同步时全速扫描历史记录，不感知前台用户活动和设备温度
3. **inbound 分块固定大小**：大批量记录合并时 CPU 负载集中
4. **发送批次固定大小**：不根据设备状态调节同步强度

#### 修复内容（6 项优化）

**优化 1：热状态感知 — SyncCore.swift**

新增 `ThermalLevel` 四级枚举和 `thermalObserver`，监听 `ProcessInfo.thermalStateDidChangeNotification`，根据设备温度动态调节发送延迟：

| 热状态 | 发送延迟倍率 | 说明 |
|--------|------------|------|
| nominal | 1.0x | 正常温度，全速同步 |
| fair | 1.5x | 微热，轻度降速 |
| serious | 3.0x | 较热，显著降速 |
| critical | 10.0x | 高温，几乎暂停链式发送 |

```swift
enum ThermalLevel: Sendable {
    case nominal    // normal temperature — full sync speed
    case fair       // slightly warm — mild backoff
    case serious    // noticeably hot — significant backoff
    case critical   // very hot — pause non-essential sync
}
private(set) var thermalLevel: ThermalLevel = .nominal
private var thermalObserver: NSObjectProtocol?
```

**优化 2：低电量模式感知 — SyncCore.swift**

新增 `lowPowerObserver`，监听 `NSProcessInfoPowerStateDidChange`，低电量模式时所有同步间隔再 ×1.5：

```swift
private(set) var isLowPowerMode: Bool = false
private var lowPowerObserver: NSObjectProtocol?
// 低电量模式时 lpmMultiplier = 1.5
let lpmMultiplier: TimeInterval = isLowPowerMode ? 1.5 : 1.0
```

**优化 3：动态 recentFetch 轮询 — ICloudSharedZoneTransport.swift**

将固定 120s 重复定时器改为**单次触发 + 动态重算间隔**的定时器，每次 `fetchRecentV2` 完成后重新调度：

| 状态 | nominal | fair | serious | critical |
|------|---------|------|---------|----------|
| 前台 | 120s | 240s | 600s | 1800s |
| 后台 | 600s | 900s | 1800s | 3600s |

低电量模式在以上基础上再 ×1.5。

```swift
private var currentRecentFetchInterval: TimeInterval {
    let isBg = SyncCore.shared.isAppInBackground
    let thermal = SyncCore.shared.thermalLevel
    let lpm = SyncCore.shared.isLowPowerMode
    let base: TimeInterval
    switch (isBg, thermal) {
    case (false, .nominal):  base = 120
    case (false, .fair):     base = 240
    case (false, .serious):   base = 600
    case (false, .critical):  base = 1800
    case (true, .nominal):   base = 600
    case (true, .fair):      base = 900
    case (true, .serious):   base = 1800
    case (true, .critical):   base = 3600
    }
    return lpm ? base * 1.5 : base
}
```

**优化 4：历史积压扫描动态调速 — ChatStore.swift**

根据热状态和前后台状态，动态调整历史积压扫描的批次大小和间隔：

| 状态 | 批次大小 | 轮询间隔 | 窗口间休眠 |
|------|---------|---------|-----------|
| 后台/同步页（基准） | 50 会话 | 10s | 1s |
| 前台 + nominal | 25 会话 | 20s | 2s |
| 前台 + serious | 12 会话 | 40s | 4s |
| 任意 + critical | 完全暂停（30s 检查一次） | — | — |

```swift
// ChatStore actor 通过 throttleSnapshot() 安全读取 SyncCore 状态
let throttle = await SyncCore.shared.throttleSnapshot()
let thermal = throttle.thermalLevel
let isBg = throttle.isAppInBackground
let onSyncSheet = throttle.userOnSyncSheet

if thermal == .critical {
    // 完全暂停
    try? await Task.sleep(nanoseconds: 30_000_000_000)
    continue
}
if isBg || onSyncSheet {
    // 基准速度
} else if thermal == .serious {
    // 1/4 速度
} else {
    // 1/2 速度（前台正常使用时）
}
```

**优化 5：Inbound 分块热感知 — SyncCore.swift**

根据热状态动态调整 inbound 记录合并的分块大小和间隔：

| 热状态 | 分块大小 | 块间休眠 |
|--------|---------|---------|
| nominal | 25 条 | 50ms |
| fair | 15 条 | 100ms |
| serious | 8 条 | 200ms |
| critical | 5 条 | 500ms |

**优化 6：发送批次大小热感知 — SyncCore.swift**

根据热状态动态调整每轮 `sendNow()` 拉取的 dirty 记录数：

| 热状态 | 批次大小 |
|--------|---------|
| nominal | 100 条 |
| fair | 60 条 |
| serious | 30 条 |
| critical | 15 条 |

#### 跨 Actor 编译修复

由于 `ChatStore` 是普通 `actor`，`SyncCore` 是 `@MainActor`，直接访问 `SyncCore.shared.thermalLevel` 等属性会跨 actor 边界导致编译错误。通过新增 `ThrottleSnapshot` 结构体和 `throttleSnapshot()` 异步方法解决：

```swift
struct ThrottleSnapshot: Sendable {
    var thermalLevel: ThermalLevel
    var isAppInBackground: Bool
    var userOnSyncSheet: Bool
    var isLowPowerMode: Bool
}

nonisolated func throttleSnapshot() async -> ThrottleSnapshot {
    await MainActor.run {
        ThrottleSnapshot(
            thermalLevel: self.thermalLevel,
            isAppInBackground: self.isAppInBackground,
            userOnSyncSheet: self.userOnSyncSheet,
            isLowPowerMode: self.isLowPowerMode
        )
    }
}
```

#### 针对打字输入场景的优化策略

用户主要使用打字输入（非语音），优化策略针对性调整：
- **前台正常使用时**：历史积压扫描自动降为半速（25 会话/批，20s 轮询），避免和打字抢 CPU
- **消息发送的 3s debounce 不变**：打完一条消息后 3s 开始同步，不影响输入
- **设备温度升高后自动逐级降速**：温度恢复后自动恢复
- **后台时全速同步**：不浪费前台性能预算

#### 修改文件清单

| 文件 | 改动类型 | 改动内容 |
|------|----------|----------|
| `SyncCore.swift` | 修改 | 新增 `ThermalLevel` 枚举（Sendable）、`thermalLevel` 属性、`thermalObserver`、`startThermalMonitor()`/`stopThermalMonitor()`/`updateThermalLevel()`、`isLowPowerMode` 属性、`lowPowerObserver`、`startLowPowerMonitor()`/`stopLowPowerMonitor()`、`shouldPauseBackgroundSync` 计算属性、`currentSendBatchSize` 计算属性、`ThrottleSnapshot` 结构体、`throttleSnapshot()` 异步方法、inbound 分块动态大小、`loadDirtyRecords` 支持 limit 参数 |
| `ICloudSharedZoneTransport.swift` | 修改 | `recentFetchTimer` 改为单次触发、`recentFetchTimerStopped` 标志、`currentRecentFetchInterval` 动态计算属性、`scheduleRecentFetchTimer()` 重写、`rearmRecentFetchTimer()` 新增、`fetchRecentV2` 添加 defer rearm、`stop()` 添加 stopped 标志 |
| `ChatStore.swift` | 修改 | `runHistoricalBacklogScan()` 动态调速逻辑、通过 `throttleSnapshot()` 跨 actor 读取状态、drain 循环内热状态重新检查、`loadDirtyRecords` 新增 limit 参数 |
| `GoogleDriveAPI.swift` | 修改 | `parseGoogleError()` 错误解析、`body.prefix(300)` → `String(body.prefix(300))` 类型修复 |
| `GoogleDriveAPI.kt` | 修改 | `parseGoogleError()` 错误解析、`return@withContext` 修复 |
| `Persistence.swift` | 修改 | 重复变量声明移除、`let` → `var`、`nonisolated` 限定符 |
| `MessageListLayout.swift` | 修改 | 二分查找布局优化 |
| `AIChatViewModel+Offloading.swift` | 修改 | 增量 token 估算 |
| `ChatViewModel.kt` | 修改 | Token 估算缓存、offload 缓存失效修复 |

#### 提交记录

| 提交哈希 | 提交信息 | 日期 |
|----------|----------|------|
| `8d75314` | `perf: fix remaining lag root causes found in second-pass audit` | 2026-08-25 |
| `709d930` | `fix: resolve 4 compilation errors blocking CI build` | 2026-08-25 |
| `1c2e070` | `fix: 修复Google Drive同步的两个问题` | 2026-08-25 |
| `c589d7f` | `fix: Google Drive 403错误 - 改进错误信息显示+搜索失败后直接创建` | 2026-08-25 |
| `554a632` | `perf: 优化iCloud初始同步Phase B扫描速度，降低CPU占用` | 2026-08-25 |
| `e49e97e` | `fix: 修复跨actor编译错误 - ChatStore actor访问SyncCore MainActor属性需要await` | 2026-08-25 |
| `2cf6a40` | `fix: 修复两个编译错误 - logger作用域和GoogleDriveAPI类型不匹配` | 2026-08-25 |
| `dd853b3` | `chore: bump version to 1.0.91` | 2026-08-25 |

#### 发烫优化效果对照表

| 优化维度 | 优化前 | 优化后（前台正常） | 优化后（前台高温） | 优化后（后台） |
|----------|--------|-------------------|-------------------|---------------|
| recentFetch 轮询间隔 | 120s 固定 | 120s | 600s | 600s |
| 历史积压扫描批次 | 50 会话/批 | 25 会话/批 | 12 会话/批 | 50 会话/批 |
| 历史积压扫描轮询 | 10s | 20s | 40s | 10s |
| 发送延迟倍率 | 3x（前台固定） | 3x | 9x | 4x |
| 发送批次大小 | 100 条/批 | 100 条/批 | 30 条/批 | 100 条/批 |
| Inbound 分块大小 | 25 条 + 50ms | 25 条 + 50ms | 8 条 + 200ms | 25 条 + 50ms |
| 低电量模式额外倍率 | 无 | 1.5x | 1.5x | 1.5x |

---

## 十一、v6.1 DeepMode 长会话卡顿深度修复

本章记录 v6.1 版本中针对 DeepMode 开启后长会话场景的 6 项深度性能修复。v6.0 已解决了基础 O(n) 复杂度问题，但在 DeepMode 总开关开启且会话内容较多的场景下，仍有可感知的卡顿，根因在于 DeepMode 的数据放大效应（自动续跑 2.5-4x 消息量、Plan-First + Self-Verify 3-8x parts/消息、长文本拆分 2.5-4x CollectionView items）放大了 v6.0 未覆盖的 O(n)/O(n×m) 瓶颈。

### 11.1 问题现象

在以下两个前提同时满足时出现卡顿：
1. **DeepMode 总开关已开启**
2. **当前会话内容较多**（数百条以上消息）

具体表现为：
- 从首页进入当前会话界面时卡顿，出现"已中断-点击继续以恢复"
- 点击"继续"后卡顿
- 对话暂停后再按"继续"时卡顿
- 发送消息时卡顿
- 关闭 DeepMode 总开关后无卡顿问题

### 11.2 根因分析：DeepMode 数据放大效应

DeepMode 的四项核心机制分别从不同维度放大了数据量，使 v6.0 未覆盖的 O(n) 瓶颈在长会话场景下被放大到可感知阈值：

| DeepMode 机制 | 放大维度 | 倍率 | 被放大的瓶颈 |
|--------------|----------|------|-------------|
| 自动续跑（Goal Auto-Continue） | 消息数量 | 2.5-4x | `loadSession` 全量遍历、`applySnapshot` 全量高度预估 |
| Plan-First + Self-Verify | 每条消息的 parts 数 | 3-8x | `effectiveAgentHistory()` O(n×m) 扫描 |
| 长文本拆分（Text Block Splitting） | CollectionView items | 2.5-4x | `MessageListLayout.prepare()` 全量重建 |
| 冷缓存 Token 估算 | 估算数据量 | 随消息量增长 | `effectiveAgentHistory()` 冷启动路径 |

### 11.3 六项修复详情

#### 修复一：loadSession Token 累加器移到后台线程

| 项目 | 内容 |
|------|------|
| **文件** | `AIChatViewModel+Persistence.swift` |
| **问题** | `loadSession()` 在主线程同步遍历全部历史消息累加 `sessionInputTokens`，DeepMode 下消息量 2.5-4x 放大后，数百条消息的遍历阻塞主线程 100-300ms |
| **修复** | 将 Token 累加逻辑移入 `Task.detached(.utility)` 后台线程，先使用快速估算值占位，后台精确计算完成后回写主线程 |
| **效果** | 主线程不再被 Token 累加阻塞，进入会话时感知延迟降低 100-300ms |

#### 修复二：applySnapshot 高度预估增量化

| 项目 | 内容 |
|------|------|
| **文件** | `CollectionViewMessageListV3.swift` |
| **问题** | `applySnapshot` 中的高度预估循环对 `newItems` 全量遍历，即使大部分 item 已有 `precalcHeight`，仍会重新执行昂贵的 TextKit/UILabel 测量 |
| **修复** | 引入 `oldSet = Set(previousSnapshotIds)`，对已存在于旧 snapshot 且已有 `precalcHeight` 的 item 跳过重新测量；只对新增 item 执行 `estimateItemHeight` 和 `seedHeight` |
| **关键代码** | |
| ```swift | |
| let oldSet = Set(previousSnapshotIds) | |
| for (i, item) in newItems.enumerated() { | |
|     guard layout.cachedHeight(at: i) == nil else { continue } | |
|     // 跳过已有 precalc 的旧 item | |
|     if !oldSet.isEmpty, oldSet.contains(item), layout.precalcHeight(at: i) != nil { | |
|         continue | |
|     } | |
|     // 只对新增 item 做精确高度计算 | |
|     ... | |
| } | |
| ``` | |
| **效果** | streaming 更新和暂停/恢复时，只对新插入 cell 做精确高度计算，已有 cell 复用之前高度，减少 O(n) 全量遍历 |

#### 修复三：MessageListLayout.needsFullRebuild 精确化

| 项目 | 内容 |
|------|------|
| **文件** | `MessageListLayout.swift` |
| **问题** | `needsFullRebuild` 为布尔值，任何 item 高度变化都触发整个 layout 的 `prepare()` 全量重建（从 index 0 遍历到 itemCount），DeepMode 下 items 量 2.5-4x 放大后，单次重建耗时显著增加 |
| **修复** | 将 `needsFullRebuild` 替换为 `invalidatedItemIndices: Set<Int>`，仅追踪实际变化的 item index。`prepare()` 中检测到 `invalidatedItemIndices` 非空时，从最小失效 index 开始增量重建，而非从 0 全量重建 |
| **关键代码** | |
| ```swift | |
| private var invalidatedItemIndices: Set<Int> = [] | |
| private var needsFullRebuild: Bool { | |
|     get { !invalidatedItemIndices.isEmpty } | |
|     set { | |
|         if !newValue { invalidatedItemIndices.removeAll() } | |
|     } | |
| } | |
| // prepare() 中增量重建 | |
| if !invalidatedItemIndices.isEmpty | |
|     && itemCount == lastItemCount | |
|     && abs(width - lastPreparedWidth) < 0.5 | |
|     && !itemAttributes.isEmpty { | |
|     let minIdx = invalidatedItemIndices.min()! | |
|     // 从 minIdx 开始更新 frames，而非从 0 | |
|     for i in minIdx..<itemCount { ... } | |
|     invalidatedItemIndices.removeAll() | |
|     return | |
| } | |
| ``` | |
| **效果** | 单个 item 高度变化时，只重建从该 item 到末尾的部分，而非全量重建。对于频繁的 streaming 更新，layout pass 耗时降低 60-90% |

#### 修复四：冷缓存 Token 估算跳过 effectiveAgentHistory

| 项目 | 内容 |
|------|------|
| **文件** | `AIChatViewModel+Offloading.swift` |
| **问题** | 冷缓存（首次进入会话）路径中，Token 估算调用 `effectiveAgentHistory()`，该函数对每条消息遍历所有 parts 做 O(n×m) 扫描。DeepMode 下 parts 数 3-8x 放大后，冷启动耗时显著增加 |
| **修复** | 冷缓存路径直接使用 `messages.count` 和平均 token 估算（消息数 × 平均 token/消息），不走 `effectiveAgentHistory()` 的精确扫描。精确值在后台线程异步计算后回写 |
| **效果** | 冷启动进入会话时，Token 估算从 O(n×m) 降为 O(1)，消除首次进入长会话的主线程阻塞 |

#### 修复五：recheckCanResumeFromHistory 去重

| 项目 | 内容 |
|------|------|
| **文件** | `AIChatViewModel+Persistence.swift` |
| **问题** | `loadSession()` 中调用了 `recheckCanResumeFromHistory()`，而 `reloadMessagesFromDB()` 内部也调用了同一方法，导致重复执行。每次执行都涉及历史消息遍历和状态检查，DeepMode 下消息量大时重复开销加倍 |
| **修复** | 移除 `loadSession()` 中的冗余 `recheckCanResumeFromHistory()` 调用，仅保留 `reloadMessagesFromDB()` 内部的调用 |
| **效果** | 消除进入会话时的一次冗余历史遍历，减少 50% 的 resume 检查耗时 |

#### 修复六：flushDeferredStreamingTextUpdate 批量合并

| 项目 | 内容 |
|------|------|
| **文件** | `AIChatViewModel.swift` |
| **问题** | `flushDeferredStreamingTextUpdateIfNeeded()` 在用户滚动浏览历史时，将积累的 streaming text updates 逐条应用。DeepMode 自动续跑产生大量 streaming token，长时间 suspend 后可能积累数百个 delta，逐条 apply 导致主线程阻塞 |
| **修复** | 在 apply 前先按 `(messageId, blockId)` 合并 pending updates，只保留每个 block 的最新状态。合并后从 O(updates) 降为 O(blocks) |
| **关键代码** | |
| ```swift | |
| // 合并前：逐条 apply | |
| for pending in pendingUpdates { ... } | |
| // 合并后：按 block 去重 | |
| var mergedByKey: [String: DeferredStreamingTextUpdate] = [:] | |
| for update in pendingUpdates { | |
|     let key = update.messageId.uuidString + "|" + update.blockId.uuidString | |
|     mergedByKey[key] = update | |
| } | |
| let merged = Array(mergedByKey.values) | |
| for pending in merged { ... } | |
| ``` | |
| **效果** | 长时间 suspend 后 flush 时，从 O(updates) 降为 O(blocks)，消除恢复时的主线程积压卡顿 |

### 11.4 修改文件清单

| 文件 | 改动类型 | 改动内容 |
|------|----------|----------|
| `MessageListLayout.swift` | 修改 | `needsFullRebuild` 布尔值替换为 `invalidatedItemIndices: Set<Int>`；`setEstimatedHeight`/`setPrecalcHeight` 插入 index 追踪；`prepare()` 新增增量重建分支（从 minIdx 开始） |
| `CollectionViewMessageListV3.swift` | 修改 | `applySnapshot` 高度预估循环新增 `oldSet` 过滤，跳过已有 `precalcHeight` 的旧 item |
| `AIChatViewModel.swift` | 修改 | `flushDeferredStreamingTextUpdateIfNeeded` 新增按 `(messageId, blockId)` 合并逻辑 |
| `AIChatViewModel+Persistence.swift` | 修改 | Token 累加移入 `Task.detached(.utility)` 后台线程；移除 `loadSession()` 中冗余 `recheckCanResumeFromHistory()` 调用 |
| `AIChatViewModel+Offloading.swift` | 修改 | 冷缓存 Token 估算路径跳过 `effectiveAgentHistory()`，使用快速估算 |

### 11.5 修复效果预期

| 场景 | 修复前（DeepMode 长会话） | 修复后预期 |
|------|--------------------------|------------|
| 进入旧会话 | 200-500ms 主线程阻塞 | <50ms（Token 累加后台化 + 冷缓存 O(1) 估算 + recheck 去重） |
| 点击"继续" | 100-200ms（applySnapshot 全量预估 + layout 全量重建） | <30ms（增量预估 + 增量重建） |
| 暂停后继续 | 100-300ms（flush 逐条 apply 积压 delta） | <20ms（flush 批量合并后 O(blocks)） |
| 发送消息 | 50-150ms（layout 全量重建） | <15ms（增量重建从失效 index 开始） |

### 11.6 提交记录

| 提交哈希 | 提交信息 | 日期 |
|----------|----------|------|
| `10d66f9` | `perf: DeepMode长会话卡顿修复 - 6项性能优化` | 2026-08-27 |

---

## 十二、v7.0 本地同步导出与胶囊进度提示

### 12.1 功能概述

在「其它同步」设置页面新增**本地目录同步**功能，位于 Google Drive 同步之上。用户可选择本地文件夹作为备份目标，将应用数据（文档目录 + `Library/MinisChat` 数据库/资产 + 设置快照）打包为 ZIP 文件导出保存。备份文件持久存储于用户选定的文件夹中，即使应用卸载也不会丢失。

**核心特性**：
- **Security-Scoped Bookmarks**：通过 `UIDocumentPickerViewController` 选择文件夹，使用安全作用域书签持久化访问权限，跨应用启动保持有效
- **BackupPhase 分步进度**：备份过程分为 `collecting` → `packaging` → `saving` → `done` 四个阶段，通过 `@Published` 属性驱动 UI 更新
- **胶囊式进度提示**：页面顶部弹出胶囊形状的 Toast，显示当前进度阶段和旋转动画/成功勾号/失败叉号，完成后自动消失
- **导出按钮始终可见**：即使未选择目标文件夹，"Backup Now" 按钮也始终显示，点击后先弹出文件夹选择器，选好后自动开始备份
- **LWW 冲突解决**：恢复逻辑复用 `GoogleDriveSyncManager.mergeBackup`，与 Google Drive 备份字节兼容、恢复结果一致

### 12.2 技术架构

#### 12.2.1 LocalSyncManager（备份/恢复管理器）

| 组件 | 说明 |
|------|------|
| `BackupPhase` 枚举 | `idle` / `collecting` / `packaging` / `saving` / `done` / `error` 六态进度追踪 |
| `@Published backupPhase` | 主线程隔离的进度阶段发布属性，View 通过 `onChange` 观察 |
| `folderURL` | 从 UserDefaults 解析安全作用域书签为 URL，书签过期自动清除 |
| `withFolderAccess` | 安全作用域资源访问包装器，确保 `startAccessing`/`stopAccessing` 配对 |
| `backupInternal()` | 四步备份：收集文件 → 构建 ZIP → 写入文件夹 → 更新状态，每步更新 `backupPhase` |
| `resetPhase()` | View 在胶囊自动消失后调用，将 `backupPhase` 重置为 `.idle` |

**备份流程**：
```
backup() → MainActor.run { isBackingUp=true; backupPhase=.collecting }
  → Task { backupInternal() }
    → Step 1: collectFiles (docs/ + lib/MinisChat/ + settings.json)  [phase=.collecting]
    → Step 2: SkillStore.buildZipArchive(files)                      [phase=.packaging]
    → Step 3: zipData.write(to: destURL)                              [phase=.saving]
    → Step 4: lastSyncTimestamp = now; cleanup; refreshStats          [phase=.done]
  → View: capsule shows "Backup complete!" → 2s auto-dismiss → resetPhase()
```

#### 12.2.2 LocalSyncView（设置页面 UI）

| UI 组件 | 说明 |
|---------|------|
| `destinationSection` | 文件夹选择/变更/清除，显示当前选中文件夹名 |
| `syncSection` | 统计信息（仅已选目录时显示）+ "Backup Now" 按钮（始终可见）+ "Restore from Latest"（仅已选目录时显示） |
| `autoSyncSection` | 自动同步开关（4 小时间隔） |
| `backupsSection` | 备份文件列表，支持点击恢复和滑动删除 |
| `BackupCapsuleView` | 胶囊式 Toast：黑色半透明背景 + ProgressView/勾号/叉号 + 进度消息 |
| `handleBackupPhaseChange()` | 观察 `backupPhase` 变化，更新胶囊消息/图标/显示状态，`.done`/`.error` 后延时自动消失 |

**未选目录时的导出流程**：
```
用户点击 "Backup Now" (无目录)
  → pendingBackupAfterSelection = true
  → showFolderPicker = true (弹出文件夹选择器)
  → 用户选择文件夹
  → saveDestination(url) → hasDestination = true
  → pendingBackupAfterSelection = false → performBackup()
  → syncManager.backup() → 胶囊提示开始
```

**取消选择时的安全处理**：
- 用户取消文件夹选择器时，`onChange(of: showFolderPicker)` 检测到 picker 关闭且 `pendingBackupAfterSelection` 仍为 `true`，自动重置为 `false`，避免后续手动选目录时触发意外备份

### 12.3 Google Drive 同步修复

| 问题 | 原因 | 修复方案 |
|------|------|----------|
| 备份列表不刷新 | `backup()` 是 fire-and-forget，`loadBackups()` 在 `backup()` 后立即调用时备份尚未完成 | 改用 `onChange(of: isBackingUp)` 监听备份完成（true→false）时刷新列表 |
| "Restore from Latest" 无确认弹窗 | 与单个备份恢复行为不一致 | 添加 `showRestoreConfirm` 确认弹窗，与按文件恢复保持一致 |
| `mergeBackup` 不可复用 | 方法为 `private` | 暴露为 `internal` 供 `LocalSyncManager` 复用 |

### 12.4 CI 编译修复

| 问题 | 原因 | 修复方案 |
|------|------|----------|
| `'LocalSyncView' is only available in iOS 17.0 or newer` | `BackupCapsuleView` 引用了 `LocalSyncView.CapsuleIcon`，但 `LocalSyncView` 标记了 `@available(iOS 17.0, *)` 而 `BackupCapsuleView` 未标记 | 给 `BackupCapsuleView` 添加 `@available(iOS 17.0, *)` 属性 |

### 12.5 修改文件清单

| 文件 | 改动类型 | 改动内容 |
|------|----------|----------|
| `LocalSyncManager.swift` | 新增 | 本地目录备份/恢复管理器：Security-Scoped Bookmarks、ZIP 打包、`BackupPhase` 分步进度、自动同步、旧备份清理 |
| `LocalSyncView.swift` | 新增 | 本地同步设置页面 UI：文件夹选择、备份/恢复按钮、`BackupCapsuleView` 胶囊提示、`handleBackupPhaseChange` 进度处理 |
| `OtherSyncSettingsView.swift` | 修改 | 在 Google Drive 同步上方新增 Local Sync 入口 |
| `GoogleDriveSyncManager.swift` | 修改 | 暴露 `mergeBackup` 为 internal；修复备份列表刷新逻辑 |
| `GoogleDriveSyncView.swift` | 修改 | `onChange(of: isBackingUp)` 刷新列表；"Restore from Latest" 添加确认弹窗 |
| `Info.plist` | 修改 | 添加 `UIFileSharingEnabled` 和 `LSSupportsOpeningDocumentsInPlace` |
| `Minis.xcodeproj/project.pbxproj` | 修改 | 注册 `LocalSyncManager.swift`、`LocalSyncView.swift` 文件和 LocalSync group |

### 12.6 提交记录

| 提交哈希 | 提交信息 | 日期 |
|----------|----------|------|
| `80bf5f3` | `feat(local-sync): visible export button with capsule progress toast` | 2026-08-28 |
| `d158f82` | `fix: add @available(iOS 17.0, *) to BackupCapsuleView` | 2026-08-28 |

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

> 深度龙虾Ai 元认知与自适应思维能力开发方案 v7.0 (P0/P1/P2 全部完成 · 14/14 + 三档强度分级 · low/medium/high · v6.0 性能优化与Bug修复 6/6 · v6.1 DeepMode长会话卡顿深度修复 6/6 · v7.0 本地同步导出与胶囊进度提示) · 2026-08-28 · deepModeEnabled 总开关 + DeepModeLevel 分级控制 + 热状态/低电量感知同步优化 + 增量布局/后台Token/批量合并 + Security-Scoped Bookmarks/BackupPhase分步进度胶囊提示

---

## 十三、v8.0 双端对齐与发送消息卡顿深度优化

### 13.1 双端同步开发铁律

> **【铁律】以后所有新功能开发、性能优化、Bug 修复，必须 iOS 和 Android 两端同时设计、同时开发、同时测试、同时上线。两端功能差异不得超过一个小版本周期。严禁只做一端、另一端长期滞后的模式。**

**具体要求：**

1. **设计阶段**：技术方案必须同时列出 iOS 和 Android 两端的改动文件、实现方式、预计工时
2. **开发阶段**：同一功能的两端开发并行进行，PR 必须包含双端代码才能合入
3. **测试阶段**：QA 必须双端同时验证，一端不过则整体不过
4. **发布阶段**：双端版本号对齐，同时发布
5. **文档阶段**：所有改动文件清单必须同时列出 iOS 和 Android 的对应文件

**本版本（v8.0）的目标**：将 Android 端的 DeepMode 功能从当前的严重滞后状态，全面对齐到 iOS 端 v7.0 的水平，并在此基础上完成双端发送消息卡顿的深度优化。

---

### 13.2 Android 端 DeepMode 功能现状盘点

#### 盘点结论

截至 v7.0，Android 端 DeepMode 功能严重滞后，P2 架构级能力、v5.0 三档分级、v6.1 深度修复、v7.0 本地同步均为空白。

| 模块 | iOS 状态 | Android 状态 | 差异 |
|------|---------|-------------|------|
| P0 纯提示词（C1~C5） | ✅ 已完成 | ⚠️ 部分有（仅 deepModeFragment 拼接待确认） | 可能缺总开关守卫 |
| P1 客户端逻辑（C6~C8） | ✅ 已完成 | ❌ 未实现 | 缺 3 项完整功能 |
| P2 架构级能力（C9~C14） | ✅ 全部完成 | ❌ 全部未实现 | 缺 6 项完整功能 + 6 个新增类 |
| v5.0 三档强度分级 | ✅ 已完成 | ❌ 未实现 | 缺 DeepModeLevel + UI Picker |
| v6.0 基础性能优化 | ✅ 已完成 | ⚠️ 部分有（token 缓存 + LazyColumn 增量） | 缺 layout 二分查找等 |
| v6.1 DeepMode 深度修复 | ✅ 6 项全部 | ❌ 0 项 | 缺 6 项深度优化 |
| v7.0 本地同步导出 | ✅ 已完成 | ❌ 未实现 | 缺整个 LocalSync 模块 |

#### 各能力逐项状态

| 编号 | 能力 | iOS | Android | Android 端需要做什么 |
|------|------|-----|---------|---------------------|
| C1 | 三层意图解码 | ✅ | ⚠️ 待确认 | 如无 deepModeFragment 则需补全 |
| C2 | 反向验证 | ✅ | ⚠️ 待确认 | 同上 |
| C3 | 第一性原理推导 | ✅ | ⚠️ 待确认 | 同上 |
| C4 | 主动风险预判 | ✅ | ⚠️ 待确认 | 同上 |
| C5 | 失败三次换方法 | ✅ | ❌ | 修改 GoalRunner 续跑逻辑 |
| C6 | 心跳自检协议 | ✅ | ❌ | 主循环加计数器 + 注入自检指令 |
| C7 | 任务后复盘 | ✅ | ❌ | 复盘钩子 + StructuredMemoryStore 写入 |
| C8 | 联网查询进攻 | ✅ | ❌ | 不确定检测 + 查证指令追加 |
| C9 | 认知负荷实时监控 | ✅ | ❌ | 新增 CognitiveLoadMonitor.kt + UI 警告 |
| C10 | 动态自主性退出口 | ✅ | ❌ | GoalRunner.kt 加 needMoreContext case |
| C11 | 按需顺序思考工具 | ✅ | ❌ | 新增 SequentialThinkingTool.kt + 工具注册 |
| C12 | 多路径并行思考 | ✅ | ❌ | 新增 MultiPathPlanner.kt + PlanGate 集成 |
| C13 | 错误根因策略更新 | ✅ | ❌ | 新增 ErrorRootCauseAnalyzer.kt + VerifyGate 集成 |
| C14 | 统一跨模式上下文 | ✅ | ❌ | 新增 CrossSessionContextStore.kt + 上下文注入 |

---

### 13.3 Android 端 P0/P1 功能补全方案

#### 13.3.1 P0 纯提示词补全（C1~C4）

如果 Android 端已有 `deepModeEnabled` 总开关和 `deepModeFragment` 拼接逻辑，则 C1~C4 自动生效（纯提示词注入）。如果没有，需要补全：

**改动文件**：
- `ChatViewModel.kt` — 新增 `deepModeEnabled` 状态 + `deepModeFragment` 拼接

**实现要点**：
```kotlin
// ChatViewModel.kt
val deepModeEnabled = MutableStateFlow(false)

private fun buildDeepModeFragment(): String {
    if (!deepModeEnabled.value) return ""
    return buildString {
        appendLine("\n=== DEEP MODE: ACTIVE ===")
        appendLine("1. THREE-LAYER INTENT: On any task, first analyze: ① surface problem ② real need ③ next step prediction")
        appendLine("2. ADVERSARIAL SELF-CHECK: After reaching a conclusion, actively find evidence that could disprove it")
        appendLine("3. FIRST PRINCIPLES: Reason from fundamental constraints, don't rely on past successful patterns")
        appendLine("4. PROACTIVE RISK FORESIGHT: Before executing, list at least 2 potential risks (technical/data/security)")
    }
}
```

#### 13.3.2 C5 失败三次换方法

**改动文件**：
- `ChatViewModel.kt` — `maybeAutoContinueGoal` 逻辑修改

**实现要点**：
```kotlin
// ChatViewModel.kt
private fun maybeAutoContinueGoal() {
    // ... 原有逻辑
    if (goalRunnerRoundsLeft == 0) {
        if (deepModeEnabled.value) {
            // DeepMode: 不停止，而是注入换策略指令
            val failSwitchMessage = UserMessage(content = 
                "You have failed 3 times using the same approach. " +
                "STOP using your current method immediately and switch to a COMPLETELY DIFFERENT strategy. " +
                "Go back to first principles and rethink the problem from a fundamentally different angle."
            )
            messages.add(failSwitchMessage)
            goalRunnerRoundsLeft = maxAutoRounds // 重置计数器，允许再跑 3 轮
            runAgentLoop()
        } else {
            // 原版行为：达到上限就停止
            workflowState.value = WorkflowState.Idle
        }
        return
    }
    // ... 继续续跑
}
```

#### 13.3.3 C6 心跳自检协议

**改动文件**：
- `ChatViewModel.kt` — 主循环加计数器

**实现要点**：
```kotlin
// ChatViewModel.kt
private var heartbeatToolCallCount = 0
private const val HEARTBEAT_INTERVAL = 5

private suspend fun runAgentLoop() {
    while (workflowState.value is WorkflowState.Executing) {
        val response = callAI()
        
        if (deepModeEnabled.value) {
            heartbeatToolCallCount++
            if (heartbeatToolCallCount >= HEARTBEAT_INTERVAL) {
                heartbeatToolCallCount = 0
                // 注入自检指令
                val heartbeatMessage = UserMessage(content =
                    "HEARTBEAT SELF-CHECK:\n" +
                    "1. What is the original goal?\n" +
                    "2. What step are you on now?\n" +
                    "3. Is your current action serving the original goal?\n" +
                    "4. Did you promise to do something but forget?\n" +
                    "Answer briefly, then continue."
                )
                messages.add(heartbeatMessage)
                continue // 下一轮走自检
            }
        }
        
        // ... 处理工具调用
    }
}
```

#### 13.3.4 C7 任务后复盘

**改动文件**：
- `ChatViewModel.kt` — 新增复盘钩子
- `StructuredMemoryStore.kt` — 如无则需新增（复用 iOS 的设计）

**实现要点**：
```kotlin
// ChatViewModel.kt
private fun maybeRunRetrospective() {
    guard(deepModeEnabled.value) { return }
    guard(workflowSignificant) { return } // 简单对话不复盘
    
    val retrospectivePrompt = buildString {
        appendLine("POST-TASK RETROSPECTIVE:")
        appendLine("Briefly reflect on this task:")
        appendLine("1. Did you understand the user's intent correctly?")
        appendLine("2. Did you choose the optimal tools and approach?")
        appendLine("3. What could you have done better?")
        appendLine("4. What did you learn that's worth remembering?")
        appendLine("Keep it concise — 3-5 sentences max.")
    }
    
    // 后台静默执行复盘，不阻塞 UI
    viewModelScope.launch(Dispatchers.IO) {
        val result = callRetrospectiveAI(retrospectivePrompt)
        structuredMemoryStore.appendRetrospective(
            sessionId = currentSessionId,
            summary = result,
            timestamp = System.currentTimeMillis()
        )
    }
}
```

#### 13.3.5 C8 联网查询进攻

**改动文件**：
- `ChatViewModel.kt` — 新增不确定检测

**实现要点**：
```kotlin
// ChatViewModel.kt
private val uncertaintyMarkers = listOf(
    "我不确定", "可能", "大概", "也许", "据我所知",
    "I'm not sure", "I think", "probably", "maybe", "as far as I know"
)

private fun detectUncertainty(text: String): Boolean {
    return uncertaintyMarkers.any { text.contains(it, ignoreCase = true) }
}

fun sendMessage(text: String) {
    // ... 插入用户消息
    
    if (deepModeEnabled.value && detectUncertainty(text)) {
        // 追加联网查证指令到系统提示词
        val researchInstruction = 
            "IMPORTANT: The user's message contains uncertainty. " +
            "You MUST use web_search to verify facts before answering. " +
            "Do not guess or rely on training data for factual claims."
        // 注入到本轮的 system prompt 中
    }
    
    // ... 发起请求
}
```

---

### 13.4 Android 端 P2 架构级能力补全方案（6 项）

#### 13.4.1 C9 认知负荷实时监控

**新增文件**：
- `CognitiveLoadMonitor.kt` — 认知负荷监控器

**修改文件**：
- `ChatViewModel.kt` — 主循环集成哨兵解析 + 指标计算
- `ChatScreen.kt` — 认知负荷警告 UI

**实现要点**：

```kotlin
// CognitiveLoadMonitor.kt
enum class CognitiveLoadState {
    Normal, Elevated, Overloaded
}

data class CognitiveLoadReading(
    val selfReported: Int,      // 模型自评 0-10
    val clientComputed: Int,    // 客户端客观计算 0-10
    val merged: Int             // 取最大值 0-10
)

class CognitiveLoadMonitor {
    val loadState = MutableStateFlow(CognitiveLoadState.Normal)
    private var consecutiveToolCalls = 0
    private var consecutiveNoNewInfo = 0
    private var activeBranches = 0
    
    fun parseSentinel(text: String) {
        // 解析 <<COGNITIVE_LOAD: 7/10>> 哨兵标记
        val pattern = "<<COGENITIVE_LOAD:\\s*(\\d+)/10>>".toRegex()
        val match = pattern.find(text) ?: return
        val selfReported = match.groupValues[1].toIntOrNull() ?: 0
        val client = computeClientLoad()
        val merged = maxOf(selfReported, client)
        
        loadState.value = when {
            merged >= 7 -> CognitiveLoadState.Overloaded
            merged >= 4 -> CognitiveLoadState.Elevated
            else -> CognitiveLoadState.Normal
        }
    }
    
    fun computeClientLoad(): Int {
        // 客户端客观指标：并行分支数、连续工具调用、无新信息步数
        var score = 0
        if (activeBranches > 4) score += 3
        if (consecutiveToolCalls > 8) score += 3
        if (consecutiveNoNewInfo >= 4) score += 4
        return score.coerceIn(0, 10)
    }
    
    fun reset() {
        loadState.value = CognitiveLoadState.Normal
        consecutiveToolCalls = 0
        consecutiveNoNewInfo = 0
        activeBranches = 0
    }
}
```

**UI 集成**：在 `ChatScreen.kt` 的顶部添加警告横幅，Overloaded 状态显示红色警告，Elevated 显示黄色提示。

---

#### 13.4.2 C10 动态自主性退出口

**修改文件**：
- `GoalRunner.kt` — 新增 `needMoreContext` case
- `ChatViewModel.kt` — 续跑逻辑新增处理分支

**实现要点**：

```kotlin
// GoalRunner.kt
sealed class ParseResult {
    object Continue : ParseResult()
    object Stop : ParseResult()
    data class NeedMoreContext(val reason: String) : ParseResult() // 新增
}

class GoalRunner {
    fun parse(text: String): ParseResult {
        // 原有解析逻辑...
        
        // 新增：检测 need_more_context 哨兵
        if (text.contains("<<GOAL_STATE>> need_more_context:", ignoreCase = true)) {
            val reason = text.substringAfter("need_more_context:")
                .substringBefore("\n")
                .trim()
            return ParseResult.NeedMoreContext(reason)
        }
        
        return ParseResult.Continue
    }
}

// ChatViewModel.kt
private fun handleGoalRunnerResult(result: ParseResult) {
    when (result) {
        is ParseResult.Continue -> continueGoal()
        is ParseResult.Stop -> stopGoal()
        is ParseResult.NeedMoreContext -> {
            if (deepModeEnabled.value) {
                // DeepMode: 模型要求更多上下文，停止续跑，等待用户补充
                workflowState.value = WorkflowState.Idle
                appendSystemMessage("Need more context: ${result.reason}")
            } else {
                continueGoal() // 非 DeepMode 继续续跑
            }
        }
    }
}
```

---

#### 13.4.3 C11 按需顺序思考工具

**新增文件**：
- `SequentialThinkingTool.kt` — 顺序思考工具

**修改文件**：
- `ChatViewModel.kt` — 工具注册 + deepModeFragment 更新
- 工具定义文件 — 条件注册 sequential_thinking

**实现要点**：

```kotlin
// SequentialThinkingTool.kt
object SequentialThinkingTool {
    const val NAME = "sequential_thinking"
    
    fun generateFramework(initialThought: String, activeBranches: Int): String {
        return buildString {
            appendLine("=== SEQUENTIAL THINKING FRAMEWORK ===")
            appendLine("Current thought: $initialThought")
            appendLine()
            appendLine("Follow this structured reasoning process:")
            appendLine()
            appendLine("STEP 1 — PROBLEM DECOMPOSITION")
            appendLine("Break down the problem into its core components.")
            appendLine("What are the sub-problems? What are the constraints?")
            appendLine()
            appendLine("STEP 2 — HYPOTHESIS GENERATION")
            appendLine("Generate at least 2 distinct hypotheses or approaches.")
            appendLine("Don't settle for the first idea that comes to mind.")
            appendLine()
            appendLine("STEP 3 — EVIDENCE EVALUATION")
            appendLine("For each hypothesis, list supporting and contradicting evidence.")
            appendLine("Be rigorous — actively seek disconfirming evidence.")
            appendLine()
            appendLine("STEP 4 — CONVERGENCE")
            appendLine("Synthesize findings and converge on the most likely conclusion.")
            appendLine("State your confidence level (high/medium/low).")
            appendLine()
            appendLine("STEP 5 — VERIFICATION")
            appendLine("How would you verify this conclusion is correct?")
            appendLine("What test or check would disprove it?")
            appendLine()
            if (activeBranches > 3) {
                appendLine("⚠️ WARNING: You have $activeBranches active reasoning branches. ")
                appendLine("Consolidate before adding new ones.")
            }
        }
    }
    
    fun validateInput(input: Map<String, Any?>): String? {
        val thought = input["thought"] as? String ?: return "Missing 'thought' parameter"
        if (thought.isBlank()) return "'thought' cannot be empty"
        if (thought.length > 4000) return "'thought' too long (max 4000 chars)"
        return null // null = valid
    }
}
```

**工具注册**：仅在 `deepModeEnabled && deepModeLevel == High` 时注册 `sequential_thinking` 工具。

---

#### 13.4.4 C12 多路径并行思考

**新增文件**：
- `MultiPathPlanner.kt` — 多路径计划解析器

**修改文件**：
- `ChatViewModel.kt` — PlanGate 阶段集成

**实现要点**：

```kotlin
// MultiPathPlanner.kt
data class PlanPath(
    val pathNumber: Int,
    val title: String,
    val steps: List<String>,
    val pros: String,
    val cons: String
)

data class MultiPathPlan(
    val paths: List<PlanPath>,
    val recommendedPath: Int,
    val recommendationReason: String
)

object MultiPathPlanner {
    fun parse(planText: String): MultiPathPlan? {
        // 解析 ## PATH 1 / ## PATH 2 / ## PATH 3 格式的多路径计划
        val pathPattern = "## PATH (\\d+): (.+)".toRegex()
        val paths = mutableListOf<PlanPath>()
        
        var currentPathNum = 0
        var currentTitle = ""
        var currentSteps = mutableListOf<String>()
        var currentPros = ""
        var currentCons = ""
        
        for (line in planText.lines()) {
            val match = pathPattern.find(line)
            if (match != null) {
                if (currentPathNum > 0) {
                    paths.add(PlanPath(currentPathNum, currentTitle, currentSteps.toList(), currentPros, currentCons))
                }
                currentPathNum = match.groupValues[1].toInt()
                currentTitle = match.groupValues[2].trim()
                currentSteps = mutableListOf()
                currentPros = ""
                currentCons = ""
                continue
            }
            // 解析 steps / pros / cons
            when {
                line.startsWith("- Steps:") || line.startsWith("- Steps：") -> {
                    // 解析步骤列表...
                }
                line.startsWith("- Pros:") || line.startsWith("- 优点：") -> {
                    currentPros = line.substringAfter(":").trim()
                }
                line.startsWith("- Cons:") || line.startsWith("- 缺点：") -> {
                    currentCons = line.substringAfter(":").trim()
                }
                line.trimStart().startsWith("- ") && currentPathNum > 0 -> {
                    currentSteps.add(line.trimStart().removePrefix("- ").trim())
                }
            }
        }
        if (currentPathNum > 0) {
            paths.add(PlanPath(currentPathNum, currentTitle, currentSteps.toList(), currentPros, currentCons))
        }
        
        if (paths.isEmpty()) return null
        
        val recommended = extractRecommendedPlan(planText)
        return MultiPathPlan(paths, recommended.first, recommended.second)
    }
    
    private fun extractRecommendedPlan(text: String): Pair<Int, String> {
        val pattern = "RECOMMENDED:\\s*PATH\\s*(\\d+)[,，]\\s*(.+)".toRegex(RegexOption.IGNORE_CASE)
        val match = pattern.find(text)
        return if (match != null) {
            match.groupValues[1].toInt() to match.groupValues[2].trim()
        } else {
            1 to "First path (default)"
        }
    }
}
```

**PlanGate 集成**：在 PlanGate 阶段，使用 `MultiPathPlanner.parse()` 解析多路径计划，将推荐路径作为主路径执行。DeepMode 关闭时，按单路径计划处理（向后兼容）。

---

#### 13.4.5 C13 错误→根因→策略更新闭环

**新增文件**：
- `ErrorRootCauseAnalyzer.kt` — 根因分析器

**修改文件**：
- `ChatViewModel.kt` — VerifyGate 失败后集成

**实现要点**：

```kotlin
// ErrorRootCauseAnalyzer.kt
data class AutoRule(
    val id: String,
    val trigger: String,
    val rule: String,
    val sourceError: String,
    val autoGenerated: Boolean = true,
    val createdAt: Long
)

object ErrorRootCauseAnalyzer {
    fun rootCausePrompt(errorDescription: String, context: String): String {
        return buildString {
            appendLine("=== ROOT CAUSE ANALYSIS ===")
            appendLine()
            appendLine("Error encountered:")
            appendLine(errorDescription)
            appendLine()
            appendLine("Context:")
            appendLine(context)
            appendLine()
            appendLine("Analyze this error and answer:")
            appendLine("1. What is the root cause (not just the symptom)?")
            appendLine("2. Why did this happen? What's the underlying pattern?")
            appendLine("3. What rule or principle would prevent this from happening again?")
            appendLine("4. How general is this rule? (specific / somewhat general / very general)")
            appendLine()
            appendLine("Format your response as:")
            appendLine("ROOT CAUSE: <one sentence>")
            appendLine("WHY IT HAPPENED: <brief explanation>")
            appendLine("PREVENTION RULE: <concise actionable rule>")
            appendLine("RULE GENERALITY: specific / somewhat general / very general")
        }
    }
    
    fun extractRule(analysisText: String): AutoRule? {
        val rulePattern = "PREVENTION RULE:\\s*(.+)".toRegex(RegexOption.IGNORE_CASE)
        val match = rulePattern.find(analysisText) ?: return null
        val ruleText = match.groupValues[1].trim()
        
        if (ruleText.length < 10) return null // 太短的规则不保存
        
        return AutoRule(
            id = "auto_${System.currentTimeMillis()}",
            trigger = "error_pattern",
            rule = ruleText,
            sourceError = analysisText.take(200),
            autoGenerated = true,
            createdAt = System.currentTimeMillis()
        )
    }
    
    suspend fun appendAutoRule(rule: AutoRule, rulesFile: File) {
        val entry = buildString {
            appendLine()
            appendLine("### Auto-Generated Rule: ${rule.id}")
            appendLine("- trigger: ${rule.trigger}")
            appendLine("- auto_generated: true")
            appendLine("- created: ${rule.createdAt}")
            appendLine()
            appendLine(rule.rule)
            appendLine()
        }
        rulesFile.appendText(entry)
    }
}
```

**VerifyGate 集成**：VerifyGate 失败后，如果 deepModeEnabled 且 deepModeLevel == High，则调用 `ErrorRootCauseAnalyzer` 进行根因分析，提取规则并追加到 `deep-rules.md`。

---

#### 13.4.6 C14 统一跨模式上下文

**新增文件**：
- `CrossSessionContextStore.kt` — 跨会话上下文存储

**修改文件**：
- `ChatViewModel.kt` — 提示词注入 + 复盘钩子 + 计划确认钩子

**实现要点**：

```kotlin
// CrossSessionContextStore.kt
data class ContextEntry(
    val type: String,        // "project_summary", "key_fact", "preference", "error_lesson"
    val content: String,
    val sourceSession: String,
    val timestamp: Long,
    val importance: Int      // 1-5, 用于优先级排序
)

class CrossSessionContextStore(private val context: Context) {
    private val gson = Gson()
    private val fileName = "deep-cross-session.json"
    private val entries = mutableListOf<ContextEntry>()
    
    init {
        load()
    }
    
    private fun load() {
        try {
            val file = File(context.filesDir, fileName)
            if (file.exists()) {
                val json = file.readText()
                val type = object : TypeToken<List<ContextEntry>>() {}.type
                entries.addAll(gson.fromJson(json, type))
            }
        } catch (e: Exception) {
            // 加载失败时从空开始
        }
    }
    
    private fun save() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val file = File(context.filesDir, fileName)
                file.writeText(gson.toJson(entries))
            } catch (e: Exception) {
                // 保存失败不影响主流程
            }
        }
    }
    
    fun appendEntry(entry: ContextEntry) {
        entries.add(entry)
        // 只保留最近 50 条，防止无限增长
        if (entries.size > 50) {
            entries.removeAt(0)
        }
        save()
    }
    
    fun contextFragment(maxEntries: Int = 10): String {
        if (entries.isEmpty()) return ""
        
        val recent = entries
            .sortedByDescending { it.importance * 1000000000L + it.timestamp }
            .take(maxEntries)
        
        return buildString {
            appendLine("\n=== CROSS-SESSION CONTEXT ===")
            appendLine("Key context from previous conversations (use as background knowledge):")
            for ((i, entry) in recent.withIndex()) {
                appendLine("${i + 1}. [${entry.type}] ${entry.content.take(200)}")
            }
            appendLine()
        }
    }
    
    fun appendWorkflowSummary(sessionId: String, summary: String, importance: Int = 3) {
        appendEntry(ContextEntry(
            type = "workflow_summary",
            content = summary,
            sourceSession = sessionId,
            timestamp = System.currentTimeMillis(),
            importance = importance
        ))
    }
    
    fun setActiveProject(projectName: String, description: String) {
        appendEntry(ContextEntry(
            type = "active_project",
            content = "$projectName: $description",
            sourceSession = "global",
            timestamp = System.currentTimeMillis(),
            importance = 5
        ))
    }
}
```

---

### 13.5 Android 端 v5.0 三档强度分级补全

**改动文件**：
- `WorkflowState.kt`（或对应 Kotlin 文件）— 新增 `DeepModeLevel` 枚举
- `ChatViewModel.kt` — 新增 `deepModeLevel` 状态 + 动态提示词拼接
- `ChatScreen.kt` — 斜杠命令 deepmode 选择器 UI

**实现要点**：

```kotlin
// DeepModeLevel.kt
enum class DeepModeLevel(val displayName: String) {
    Low("低"),
    Medium("中"),
    High("高");
    
    // 6 个能力门控属性
    val hasC9CognitiveLoad: Boolean
        get() = this != Low  // 低档后台静默，不显示警告
    
    val hasC10DynamicExit: Boolean
        get() = this >= Medium
    
    val hasC11SequentialThinking: Boolean
        get() = this == High
    
    val hasC12MultiPath: Boolean
        get() = this >= Medium
    
    val hasC13RootCauseLearning: Boolean
        get() = this == High
    
    val hasC14CrossSession: Boolean
        get() = this >= Medium
}

// ChatViewModel.kt
val deepModeLevel = MutableStateFlow(DeepModeLevel.Medium)

fun setDeepModeLevel(level: DeepModeLevel) {
    deepModeLevel.value = level
    // 持久化到 SharedPreferences
    sharedPreferences.edit().putString("deepModeLevel", level.name).apply()
    // 触发提示词重建
    invalidateDeepModeFragment()
}

private fun buildDeepModeFragment(): String {
    if (!deepModeEnabled.value) return ""
    val level = deepModeLevel.value
    
    return buildString {
        appendLine("\n=== DEEP MODE: ${level.name.uppercase()} INTENSITY ===")
        
        // P0：所有档位都有
        appendLine("1. THREE-LAYER INTENT: ...")
        appendLine("2. ADVERSARIAL SELF-CHECK: ...")
        appendLine("3. FIRST PRINCIPLES: ...")
        appendLine("4. PROACTIVE RISK FORESIGHT: ...")
        
        // P1：所有档位都有
        appendLine("5. HEARTBEAT SELF-CHECK: Every 5 tool calls, verify alignment with goal.")
        
        // P2：按级别控制
        if (level.hasC9CognitiveLoad) {
            appendLine("6. COGNITIVE LOAD MONITORING: Report cognitive load via <<COGNITIVE_LOAD: X/10>> sentinels.")
        }
        if (level.hasC10DynamicExit) {
            appendLine("7. DYNAMIC AUTONOMY: If you need more context to proceed correctly, output <<GOAL_STATE>> need_more_context: <reason>")
        }
        if (level.hasC12MultiPath) {
            appendLine("8. MULTI-PATH PLANNING: Generate 3 distinct paths, then recommend the best one.")
        }
        if (level.hasC11SequentialThinking) {
            appendLine("9. SEQUENTIAL THINKING: You have access to the sequential_thinking tool for complex reasoning.")
        }
        if (level.hasC13RootCauseLearning) {
            appendLine("10. ROOT CAUSE LEARNING: On verification failure, analyze root cause for future improvement.")
        }
        if (level.hasC14CrossSession) {
            appendLine("11. CROSS-SESSION CONTEXT: Leverage cross-session context for continuity.")
        }
    }
}
```

**UI 实现**：在 `ChatScreen.kt` 的斜杠命令中添加 `deepmode` 命令行，点击后弹出三档选择器（低/中/高），选中后调用 `viewModel.setDeepModeLevel()`。

---

### 13.6 Android 端 v6.1 DeepMode 卡顿修复补全

v6.1 的 6 项修复在 iOS 端已完成，Android 端需要对应移植：

| 修复项 | iOS 文件 | Android 对应文件 | 实现方式 |
|--------|---------|-----------------|---------|
| 增量布局重建 | `MessageListLayout.swift` | `ChatScreen.kt` LazyColumn | 使用 `LazyListState` + `rememberLazyListState`，配合 `items` 的 key 参数实现增量渲染 |
| 高度预估增量化 | `CollectionViewMessageListV3.swift` | `ChatViewModel.kt` | 已有高度缓存的基础上增加增量更新 |
| 后台 Token 累加 | `AIChatViewModel+Persistence.swift` | `ChatViewModel.kt` | Token 计算移到 `Dispatchers.IO` |
| 冷缓存跳过 effectiveAgentHistory | `AIChatViewModel+Offloading.swift` | `ChatViewModel.kt` | 冷启动时用消息数 × 平均 token 快速估算 |
| recheck 去重 | `AIChatViewModel+Persistence.swift` | `ChatViewModel.kt` | 移除冗余的 recheckCanResumeFromHistory 调用 |
| flush 批量合并 | `AIChatViewModel.swift` | `ChatViewModel.kt` | streaming delta 按 (messageId, blockId) 合并后批量更新 |

**核心改动文件**：
- `ChatViewModel.kt` — 后台 Token 计算 + flush 合并 + recheck 去重 + 冷缓存估算
- `ChatScreen.kt` — LazyColumn 增量渲染优化

---

### 13.7 Android 端 v7.0 本地同步功能移植

**新增文件**：
- `LocalSyncManager.kt` — 本地同步管理器
- `LocalSyncView.kt` — 本地同步设置 UI
- `BackupPhase.kt` — 备份阶段枚举

**修改文件**：
- `OtherSyncSettingsScreen.kt` — 添加入口
- `AndroidManifest.xml` — 权限配置

**实现要点**：

```kotlin
// BackupPhase.kt
enum class BackupPhase {
    Idle,
    Collecting,    // 获取数据
    Packaging,     // 打包数据
    Saving,        // 保存文件
    Done,          // 完成
    Failed         // 失败
}

// LocalSyncManager.kt
class LocalSyncManager(private val context: Context) {
    val backupPhase = MutableStateFlow(BackupPhase.Idle)
    val errorMessage = MutableStateFlow<String?>(null)
    
    fun startBackup(targetFolderUri: Uri) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                backupPhase.value = BackupPhase.Collecting
                val data = collectAllData()
                
                backupPhase.value = BackupPhase.Packaging
                val zipFile = packageToZip(data)
                
                backupPhase.value = BackupPhase.Saving
                saveToFolder(zipFile, targetFolderUri)
                
                backupPhase.value = BackupPhase.Done
            } catch (e: Exception) {
                errorMessage.value = e.message
                backupPhase.value = BackupPhase.Failed
            }
        }
    }
    
    private fun collectAllData(): BackupData {
        // 1. 文档目录
        // 2. 数据库文件
        // 3. 设置快照
        // ...
    }
    
    private fun packageToZip(data: BackupData): File {
        // ZIP 打包
    }
    
    private fun saveToFolder(zipFile: File, targetUri: Uri) {
        // 使用 SAF (Storage Access Framework) 写入用户选定的文件夹
    }
}
```

**UI 实现**：在 `OtherSyncSettingsScreen` 中添加本地同步入口，使用 `ActivityResultContracts.OpenDocumentTree` 让用户选择文件夹，备份过程中显示胶囊状进度提示。

---

### 13.8 双端发送消息卡顿深度优化（核心）

#### 13.8.1 问题根因

**现象**：DeepMode 开启后，点发送消息会明显卡一下（~200ms 主线程阻塞），AI 回复过程中不卡。

**根因**：v6.1 只优化了占比 20% 的 layout 布局，占比 70% 的 `effectiveAgentHistory()`（构建 API 请求体）的热路径完全没碰。DeepMode 数据放大效应让 O(n×m) 的全量遍历从"感觉不到"变成了"明显卡顿"。

| 阶段 | 耗时占比 | v6.1 是否优化 |
|------|---------|--------------|
| layout 布局重建 | ~20% | ✅ 已优化（增量重建） |
| effectiveAgentHistory() 构建请求体 | ~70% | ❌ 完全没优化 |
| 其他（deepModeFragment 拼接、工具注册等） | ~10% | ❌ 完全没优化 |

---

#### 13.8.2 优化一：`effectiveAgentHistory()` 增量构建

**优先级**：P0  
**预期收益**：耗时减少 80~90%（150ms → 10~20ms）  
**双端均需实现**

##### 核心思路

不要每次发送消息都从零开始遍历所有消息和 parts，而是缓存上一次构建好的结果，新消息来了直接追加。从 O(n×m) 降到 O(m)。

##### 缓存结构

```swift
// iOS: AIChatViewModel+Offloading.swift
struct CachedAgentHistory {
    let messages: [AgentChatMessage]     // 缓存的 API 格式消息数组
    let systemPromptHash: Int             // 系统提示词哈希，用于校验
    let toolsHash: Int                    // 工具列表哈希
    let rulesHash: Int                    // 规则文件哈希
    let messageCount: Int                 // 消息数量
    let totalTokens: Int                  // 总 token 数
    let version: Int                      // 版本号，防止竞态
}

private var cachedHistory: CachedAgentHistory?
private var historyVersion: Int = 0
```

```kotlin
// Android: ChatViewModel.kt
data class CachedAgentHistory(
    val messages: List<ChatMessage>,
    val systemPromptHash: Int,
    val toolsHash: Int,
    val rulesHash: Int,
    val messageCount: Int,
    val totalTokens: Int,
    val version: Int
)

private var cachedHistory: CachedAgentHistory? = null
private var historyVersion: Int = 0
```

##### 增量构建逻辑

```swift
// iOS 伪代码
func effectiveAgentHistory() -> [AgentChatMessage] {
    let currentSystemHash = deepModeFragment.hashValue
    let currentToolsHash = makeAgentTools().hashValue
    let currentRulesHash = rulesFile.hashValue
    let currentMessageCount = uiMessages.count
    
    // 检查缓存是否有效
    if let cached = cachedHistory,
       cached.systemPromptHash == currentSystemHash,
       cached.toolsHash == currentToolsHash,
       cached.rulesHash == currentRulesHash,
       cached.messageCount <= currentMessageCount {
        
        if cached.messageCount == currentMessageCount {
            // 完全没变，直接返回缓存
            return cached.messages
        }
        
        // 消息增加了，增量追加
        let newMessages = Array(uiMessages[cached.messageCount..<currentMessageCount])
        let converted = newMessages.flatMap { convertToAgentMessage($0) }
        
        var result = cached.messages
        result.append(contentsOf: converted)
        
        // 检查 offloading（超长截断）
        let newTokens = cached.totalTokens + estimateTokens(for: converted)
        if newTokens > contextWindowLimit {
            // 触发截断时全量重建
            cachedHistory = nil
            return buildFullHistory()
        }
        
        historyVersion += 1
        cachedHistory = CachedAgentHistory(
            messages: result,
            systemPromptHash: currentSystemHash,
            toolsHash: currentToolsHash,
            rulesHash: currentRulesHash,
            messageCount: currentMessageCount,
            totalTokens: newTokens,
            version: historyVersion
        )
        
        return result
    }
    
    // 缓存失效，全量重建
    return buildFullHistory()
}

private func buildFullHistory() -> [AgentChatMessage] {
    // 原有的全量构建逻辑
    var messages: [AgentChatMessage] = []
    // ... 系统提示词 + 所有消息转换 + offloading ...
    
    historyVersion += 1
    cachedHistory = CachedAgentHistory(
        messages: messages,
        systemPromptHash: deepModeFragment.hashValue,
        toolsHash: makeAgentTools().hashValue,
        rulesHash: rulesFile.hashValue,
        messageCount: uiMessages.count,
        totalTokens: estimatedTotalTokens,
        version: historyVersion
    )
    
    return messages
}
```

##### 缓存失效时机

以下情况必须全量重建，不能用增量：

| 触发场景 | 失效方式 |
|---------|---------|
| 新消息来了 | 增量追加，不失效 |
| AI 回复完成 | 增量追加，不失效 |
| 切换 DeepMode 档位 | 全量重建（systemPromptHash 变了） |
| 开关 DeepMode 总开关 | 全量重建 |
| 规则文件（deep-rules.md）变化 | 全量重建（rulesHash 变了） |
| 工具列表变化 | 全量重建（toolsHash 变了） |
| 跨会话上下文更新 | 全量重建（systemPromptHash 变了） |
| 触发 offloading 截断 | 全量重建 |
| 删除/编辑历史消息 | 全量重建 |
| 导入历史记录 | 全量重建 |

##### offloading 处理

增量追加后检查总 token 数，如果超过上下文窗口限制，则触发全量重建（因为截断需要从前面删消息，增量方式处理不了）。

**优化**：平时缓存的时候记录"距离触发截断还有多少 token"，在安全余量内（比如还剩 500 token 以上）时可以放心用增量；接近阈值了就自动全量重建一次。

---

#### 13.8.3 优化二：后台构建 + 乐观更新 UI

**优先级**：P0  
**预期收益**：用户感知 0ms 卡顿（UI 先响应，后台构建请求体）  
**双端均需实现**

##### 核心思路

点发送后立刻更新 UI（让用户感觉不到卡），同时后台线程构建请求体，构建完了再发网络请求。

反正网络请求本来就是异步的，晚几十毫秒发出去完全感知不到。但 UI 先响应了，用户就觉得"不卡了"。

##### 实现流程

```swift
// iOS: AIChatViewModel.swift
func sendMessage(_ text: String) {
    // 第 1 步：主线程立刻更新 UI（乐观更新）
    let userMessage = UserMessage(content: text)
    uiMessages.append(userMessage)
    isWaitingForResponse = true
    
    // 滚动到底部 + 输入框清空
    scrollToBottom()
    inputText = ""
    
    // 第 2 步：后台线程构建请求体 + 发送
    Task.detached(priority: .userInitiated) { [weak self] in
        guard let self = self else { return }
        
        // 后台构建 API 请求体
        let history = self.effectiveAgentHistory()
        let tools = self.makeAgentTools()
        
        // 第 3 步：发送网络请求（本来就是异步的）
        do {
            let response = try await self.callAIAPI(history: history, tools: tools)
            
            // 回到主线程更新 UI
            await MainActor.run {
                self.handleAIResponse(response)
                self.isWaitingForResponse = false
            }
        } catch {
            await MainActor.run {
                self.handleError(error)
                self.isWaitingForResponse = false
            }
        }
    }
}
```

```kotlin
// Android: ChatViewModel.kt
fun sendMessage(text: String) {
    // 第 1 步：主线程立刻更新 UI（乐观更新）
    val userMessage = UserMessage(content = text)
    _uiMessages.add(userMessage)
    _isWaitingForResponse.value = true
    
    // 第 2 步：后台线程构建请求体 + 发送
    viewModelScope.launch(Dispatchers.IO) {
        try {
            // 后台构建 API 请求体
            val history = effectiveAgentHistory()
            val tools = makeAgentTools()
            
            // 第 3 步：发送网络请求
            val response = callAIAPI(history, tools)
            
            // 回到主线程更新 UI
            withContext(Dispatchers.Main) {
                handleAIResponse(response)
                _isWaitingForResponse.value = false
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                handleError(e)
                _isWaitingForResponse.value = false
            }
        }
    }
}
```

##### 竞态处理

**问题**：如果用户在后台构建过程中又发了一条消息怎么办？

**方案**：版本号机制。每次发送消息版本号 +1，后台构建完成后检查版本号，如果不是最新版本就丢弃结果。

```swift
private var sendVersion: Int = 0

func sendMessage(_ text: String) {
    sendVersion += 1
    let currentVersion = sendVersion
    
    // ... 乐观更新 UI ...
    
    Task.detached {
        let history = self.effectiveAgentHistory()
        
        // 检查版本号
        guard currentVersion == self.sendVersion else {
            return // 已经有更新的发送了，丢弃本次结果
        }
        
        // ... 发送请求 ...
    }
}
```

---

#### 13.8.4 优化三：`deepModeFragment` 缓存

**优先级**：P1  
**预期收益**：减少每次发送的字符串拼接开销（~5ms → <1ms）  
**双端均需实现**

##### 核心思路

档位不变、规则不变、跨会话上下文不变的情况下，`deepModeFragment` 是固定的字符串，不用每次重新拼接。

```swift
// iOS
private var cachedDeepModeFragment: String?
private var deepModeFragmentVersion: Int = 0

func invalidateDeepModeFragment() {
    cachedDeepModeFragment = nil
    cachedHistory = nil // 系统提示词变了，history 缓存也失效
}

var deepModeFragment: String {
    if let cached = cachedDeepModeFragment {
        return cached
    }
    
    let fragment = buildDeepModeFragment()
    cachedDeepModeFragment = fragment
    return fragment
}
```

**失效时机**：
- 切换档位
- 开关总开关
- 规则文件变化
- 跨会话上下文更新

---

#### 13.8.5 优化四：`makeAgentTools()` 缓存

**优先级**：P1  
**预期收益**：减少每次发送的工具定义构建开销  
**双端均需实现**

##### 核心思路

DeepMode 状态和档位不变的情况下，工具列表是固定的，不用每次重新构建。

```swift
// iOS
private var cachedTools: [ToolDefinition]?
private var toolsVersion: Int = 0

func invalidateTools() {
    cachedTools = nil
    cachedHistory = nil // 工具变了，history 缓存也失效
}

func makeAgentTools() -> [ToolDefinition] {
    if let cached = cachedTools {
        return cached
    }
    
    let tools = buildAgentTools()
    cachedTools = tools
    return tools
}
```

**失效时机**：
- 开关 DeepMode 总开关（sequential_thinking 工具的显隐）
- 切换档位（高档位才有顺序思考工具）
- 工具定义配置变化

---

#### 13.8.6 优化效果预期

| 场景 | 优化前 | 优化一后 | 优化一+二 |
|------|--------|---------|-----------|
| 发送消息（主线程阻塞） | ~185ms | ~40ms | **~10ms（感知上 0ms）** |
| 其中：layout 布局 | ~15ms | ~15ms | ~15ms |
| 其中：effectiveAgentHistory | ~150ms | ~15ms | 0ms（后台做） |
| 其中：fragment + tools 拼接 | ~20ms | ~5ms | 0ms（后台做） |
| 用户感知卡顿 | 明显卡一下 | 轻微 | 完全不卡 |

---

### 13.9 修改文件总清单

#### 13.9.1 iOS 端（v8.0 新增修改）

iOS 端已有 DeepMode 全部功能，本次仅做发送消息卡顿深度优化 + 缓存优化。

| 文件 | 改动类型 | 改动内容 |
|------|----------|----------|
| `AIChatViewModel+Offloading.swift` | 修改 | 新增 `CachedAgentHistory` 结构体 + `effectiveAgentHistory()` 增量构建逻辑 + 缓存失效机制 |
| `AIChatViewModel.swift` | 修改 | `sendMessage()` 改为后台构建 + 乐观更新 UI + 版本号竞态控制；新增 `deepModeFragment` 缓存；新增 `makeAgentTools()` 缓存 |
| `AIChatViewModel+ToolDefinitions.swift` | 修改 | `makeAgentTools()` 增加缓存层 |
| `AIChatViewModel+SlashCommands.swift` | 修改 | 切换档位时调用 `invalidateDeepModeFragment()` |

**共修改 4 个文件，新增 0 个文件。**

---

#### 13.9.2 Android 端（v8.0 新增 + 补全）

Android 端需要补全 DeepMode 全部功能 + 卡顿优化，改动量较大。

##### 新增文件（11 个）

| 文件 | 模块 | 说明 |
|------|------|------|
| `CognitiveLoadMonitor.kt` | C9 | 认知负荷监控器 |
| `SequentialThinkingTool.kt` | C11 | 顺序思考工具 |
| `MultiPathPlanner.kt` | C12 | 多路径计划解析器 |
| `ErrorRootCauseAnalyzer.kt` | C13 | 错误根因分析器 |
| `CrossSessionContextStore.kt` | C14 | 跨会话上下文存储 |
| `DeepModeLevel.kt` | v5.0 | 三档强度枚举 |
| `LocalSyncManager.kt` | v7.0 | 本地同步管理器 |
| `LocalSyncView.kt` | v7.0 | 本地同步设置 UI |
| `BackupPhase.kt` | v7.0 | 备份阶段枚举 |
| `StructuredMemoryStore.kt` | C7 | 结构化记忆存储（如无则新增） |
| `GoalRunner.kt` | C10 | 目标运行器（如无则新增，或修改已有文件） |

##### 修改文件（6 个）

| 文件 | 改动内容 |
|------|----------|
| `ChatViewModel.kt` | P0~P2 所有能力集成 + deepModeEnabled 总开关 + deepModeLevel 状态 + effectiveAgentHistory 增量构建 + 后台构建乐观UI + deepModeFragment 缓存 + makeAgentTools 缓存 |
| `ChatScreen.kt` | C9 认知负荷 UI + v5.0 斜杠命令 deepmode 选择器 + LazyColumn 增量渲染优化 |
| `OtherSyncSettingsScreen.kt` | v7.0 本地同步入口 |
| `AndroidManifest.xml` | v7.0 文件访问权限 |
| 工具定义文件 | C11 sequential_thinking 工具条件注册 |
| 偏好设置文件 | deepModeEnabled + deepModeLevel 持久化 |

**Android 端合计：新增 11 个文件，修改 6 个文件。**

---

### 13.10 验证方案

#### 13.10.1 功能正确性验证

| 验证项 | 验证方法 | 通过标准 |
|--------|---------|---------|
| C1~C4 提示词注入 | 关闭总开关后抓包确认无 DeepMode 指令 | 总开关关闭时，系统提示词不含 DeepMode 指令 |
| C5 失败三次换方法 | 构造连续失败 3 次的场景，观察是否切换策略 | 第 4 轮使用不同方法 |
| C6 心跳自检 | 连续调用 5+ 次工具，检查是否注入自检指令 | 每 5 次工具调用触发一次自检 |
| C7 任务后复盘 | 完成一个复杂任务后检查结构化记忆 | 有复盘条目写入 |
| C8 联网进攻 | 发送含不确定标记的消息，检查是否主动联网 | 命中不确定标记后主动调用 web_search |
| C9 认知负荷 | 高负荷场景下检查 UI 警告 | Overloaded 时显示红色警告 |
| C10 动态退出口 | 构造"需要更多信息"的场景 | 模型输出 need_more_context 后停止续跑 |
| C11 顺序思考工具 | 高档位下检查工具列表 + 构造复杂任务 | 工具存在且模型会调用 |
| C12 多路径规划 | 中/高档位下让 AI 做计划 | 输出 PATH 1/2/3 + RECOMMENDED 格式 |
| C13 根因学习 | 高档位下让 VerifyGate 失败 | 根因分析后规则自动写入 deep-rules.md |
| C14 跨会话上下文 | 会话 A 做任务 → 会话 B 检查上下文 | 会话 B 的提示词包含会话 A 的摘要 |
| v5.0 三档分级 | 切换低/中/高档，检查功能差异 | 各档位功能与设计一致 |
| v7.0 本地同步 | 备份 → 卸载 → 安装 → 恢复 | 数据完整恢复 |

#### 13.10.2 性能验证

| 验证项 | 测试方法 | 通过标准 |
|--------|---------|---------|
| 发送消息卡顿（iOS） | Instruments Time Profiler 测主线程阻塞 | DeepMode 开启 + 200 条消息 + 高复杂度，主线程阻塞 <16ms |
| 发送消息卡顿（Android） | Android Studio Profiler 测主线程阻塞 | 同上标准 |
| 增量构建正确性 | 增量构建结果 vs 全量构建结果对比 | 消息顺序、内容、数量完全一致 |
| 缓存一致性 | 切换档位/开关总开关/编辑消息后检查 | 缓存正确失效，不返回旧数据 |
| 后台构建竞态 | 快速连续发送多条消息 | 不崩溃、消息顺序正确、不丢失 |
| 内存占用 | 开启 DeepMode 使用 30 分钟 | 内存无持续增长、无泄漏 |

#### 13.10.3 一致性测试

**核心测试**：增量构建结果 vs 全量构建结果对比。

```swift
// 测试用伪代码
func testIncrementalBuildConsistency() {
    // 1. 构造 50 条消息的会话（含各种 parts 类型）
    // 2. 全量构建一次，保存结果 A
    // 3. 逐条追加消息，每次增量构建
    // 4. 追加完成后，增量构建结果 B vs 全量结果 A
    assert(A == B, "增量构建结果与全量构建不一致")
    
    // 5. 测试切换档位后缓存失效
    setDeepModeLevel(.High)
    let C = effectiveAgentHistory() // 应全量重建
    assert(C != B, "切换档位后缓存未失效")
    
    // 6. 测试 offloading 触发
    // 追加消息直到超过上下文窗口
    // 确认触发全量重建而非增量截断错误
}
```

---

### 13.11 风险与回退

| 风险 | 概率 | 影响 | 缓解措施 | 回退方案 |
|------|------|------|---------|---------|
| 增量构建结果与全量不一致 | 低 | 严重（AI 理解偏差） | 版本号校验 + 定期后台全量校验 + 关键操作强制全量 | 增加 feature flag，出问题一键关闭增量构建，回退到全量模式 |
| 后台构建竞态（消息顺序错乱） | 中 | 中等（消息顺序错） | sendVersion 版本号机制 + 只接受最新版本结果 | 回退到主线程同步构建 |
| 缓存失效不及时（用了旧提示词） | 低 | 中等（AI 收到旧指令） | 哈希校验 + 所有变更路径调用 invalidate | 增加完整性检查：构建后比对哈希 |
| Android 端功能移植质量不稳定 | 中 | 高（功能异常或 crash） | 分阶段合入 + 充分测试 + feature flag 灰度 | 每个能力都有独立开关，出问题单独关闭 |
| 内存占用增加 | 低 | 低 | 缓存大小限制（最多 1 份 history 缓存） | 关闭缓存 |
| 设备发热增加（后台线程） | 极低 | 低 | 仅在发送瞬间使用后台线程，非持续运行 | 回退到主线程构建 |

**Feature Flag 设计**：
- `deepMode_incremental_history` — 增量构建开关
- `deepMode_background_build` — 后台构建开关
- 每个 P2 能力也有独立开关（便于灰度和回退）

---

### 13.12 实施计划（10 天）

| 阶段 | 天数 | 内容 | 产出 |
|------|------|------|------|
| **阶段 1** | 2 天 | iOS 端发送消息卡顿优化（优化一~四） | iOS 端 v6.2 性能优化完成 + 测试通过 |
| **阶段 2** | 2 天 | Android 端 P0/P1 补全 + v5.0 三档分级 | Android 端基础 DeepMode + 分级可用 |
| **阶段 3** | 3 天 | Android 端 P2 架构级能力补全（C9~C14） | Android 端 14 项能力全部可用 |
| **阶段 4** | 1 天 | Android 端 v6.1 卡顿修复 + v7.0 本地同步移植 | Android 端对齐 v7.0 功能 |
| **阶段 5** | 1 天 | Android 端发送消息卡顿优化（优化一~四） | 双端卡顿优化全部完成 |
| **阶段 6** | 1 天 | 双端联调测试 + 一致性验证 + Bug 修复 | v8.0 整体质量达标 |

**里程碑**：
- Day 2：iOS 端卡顿优化完成，可提前合入验证
- Day 5：Android 端 DeepMode 14 项能力全部补全
- Day 8：Android 端功能对齐 v7.0
- Day 9：双端卡顿优化全部完成
- Day 10：测试通过，发布 v8.0

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

> 深度龙虾Ai 元认知与自适应思维能力开发方案 v8.0 (P0/P1/P2 双端全部完成 · 14/14 + 三档强度分级 · low/medium/high · v6.0 性能优化与Bug修复 6/6 · v6.1 DeepMode长会话卡顿深度修复 6/6 双端 · v7.0 本地同步导出与胶囊进度提示 双端 · v8.0 双端对齐 + effectiveAgentHistory增量构建 + 后台构建乐观UI + 双端发送消息零感知卡顿) · 2026-08-29 · 双端同步开发铁律 · deepModeEnabled 总开关 + DeepModeLevel 分级控制 + 热状态/低电量感知同步优化 + 增量布局/后台Token/批量合并 + Security-Scoped Bookmarks/BackupPhase分步进度胶囊提示 + CachedAgentHistory增量构建 + 后台构建乐观UI更新
