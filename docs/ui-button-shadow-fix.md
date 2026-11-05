# 按钮「阴影」问题：完整清单与修复记录

> 仓库：`hf805864818/deepseek-ai`（LobsterAi）
> 影响环境：用 **iOS 26 SDK** 编译、运行在 **iOS 17** 的设备
> 覆盖版本：`1.0.245` 起，逐项修复至 `1.0.251` / `1.0.254`

---

## 一、逐按钮清单（修复台账）

「灰方块」指比按钮本身大一圈的灰色圆角矩形；「投影」指容器外围的柔和阴影。

### 1. 聊天输入区

| 按钮 | 视图 / 文件 | 修复前 | 修复后 | 手段 | commit |
|---|---|---|---|---|---|
| `+` 附件 | `AIChatView+ComposerControls.swift` `attachmentMenuButton` | 浅灰圆 + 灰方块底 | 透明底 + 0.78 灰细边 | `inputIconBg → clear` + 根部 `buttonStyle(.plain)` | `7cc6978` / `c40090c` / `db27f43` |
| `/` 斜杠命令 | 同上，`slashButton` | 灰方块 + 白圆 | 透明 + 细边 | 同上 | 同上 |
| 麦克风 | `Composer/MicButton.swift` | 浅灰圆 + 灰方块 | 透明 + 细边 | 同上 | 同上 |
| 发送 | `Composer/ChatSendButton.swift` | 灰方块 + 灰圆 | 透明 + 细边（禁用态仍为 `quaternaryLabel`） | 同上 | 同上 |
| 语言徽标 | `AIChatView+ComposerControls.swift` `languageBadgeButton` | 灰方块 + 白圆 | 透明 + 细边 | 同上 | 同上 |
| 「语音输入 · 系统识别（在线）」胶囊 | `Views/Chat/Voice/InlineVoiceInputView.swift` | 胶囊外一圈灰底 | **未修**（见 §五 待办） | — | — |

### 2. 聊天消息区

| 按钮 | 视图 / 文件 | 修复前 | 修复后 | 手段 | commit |
|---|---|---|---|---|---|
| `↑` 回顶 | `AIChatView+MessagesArea.swift` `scrollFloatingButtonLabel("arrow.up.to.line")` | 灰方块 + 白圆 | 白圆 + 0.35 灰边 | `Button` 后加 `.buttonStyle(.plain)` | `db27f43` |
| `↓` 回底 | 同上 `("chevron.down")` | 灰方块 + 白圆 | 同上 | 同上 | `db27f43` |

### 3. 语音输入面板

| 按钮 | 视图 / 文件 | 状态 |
|---|---|---|
| `⌄` 收起 | `InlineVoiceInputView.swift` | **未修**（待办） |
| `/`、发送、键盘 | 同上（复用 composer 组件的一部分） | 部分随 `inputIconBg` 变化，`buttonStyle` 待补 |

### 4. 终端 Minis Shell

| 按钮 | 视图 / 文件 | 修复前 | 修复后 | 手段 | commit |
|---|---|---|---|---|---|
| `隐藏` `粘贴` `Esc` `Tab` | `Views/Rootfs/ISHTerminalView.swift` `QuickCommandButton` | 深色底上多一块浅灰底板 | 只有 `Color(white: 0.25)` 胶囊 | `Button` 加 `.buttonStyle(.plain)` | `07e2a63` |
| 方向键 / `Ctrl` / `C-c`/`C-d`/`C-z` / `Files` / `Rootfs` | 同上（同一个组件） | 同上 | 同上 | 同上 | `07e2a63` |

### 5. 容器级（不是按钮，但被当成阴影）

| 对象 | 文件 | 修复前 | 修复后 | commit |
|---|---|---|---|---|
| 输入区整体 | `Composer/ComposerSurface.swift`（`else` 分支） | 两条 `.shadow`：下投 `black 0.12 / r8 / y2`、暗色上投 `black 0.5 / r8 / y-4` | 删除两条投影，改 `.overlay(shape.stroke(inputBorder.opacity(0.6), 0.5))` | `462713d` |

---

## 二、根因

### 根因 A：iOS 26 SDK 的默认 Button 样式

`Button` 的默认样式由**编译 SDK** 决定，不是运行系统。用 iOS 26 SDK 编译、跑在 iOS 17 时，系统会在 label 背后铺一块灰色圆角矩形（26 上是 Liquid Glass 的一部分，17 上退化成实心灰底）。

自绘的 `Circle()` + 0.5pt 描边盖不住它，于是「灰方块 + 白圆」叠影。

**同屏对照证据**：

| 按钮 | 代码 | 结果 |
|---|---|---|
| 静音「朗…」 | 有 `.buttonStyle(.plain)`（`ComposerControls:191`） | 无底板 |
| `+` / `/` / 发送 / `↑` / `↓` / 终端快捷键 | 没有 `buttonStyle` | 全部有底板 |

### 根因 B：容器在 iOS < 26 上的两条投影

```swift
if #available(iOS 26.0, *) {
    content.glassEffect(.regular, in: shape)          // 26+ 玻璃自带边缘，无需手绘
} else {
    content
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .shadow(color: … dark ? .black.opacity(0.5) : .clear …, radius: 8, y: -4)
}
```

iOS 17 走 `else`，整条输入区拖着一圈投影，与按钮灰底叠加，加重「阴影」观感。

---

## 三、修复方法（可复用的三步）

**第一步：给会自绘外观的按钮显式去掉系统样式**

```swift
Button { … } label: { … }
    .buttonStyle(.plain)
```

优先级：能加在**父容器**上就不要逐个加（SwiftUI 的 buttonStyle 向下传递）。例如输入栏是一条 `.buttonStyle(.plain)` 覆盖整行。

**第二步：清掉自绘的多余底色**

```swift
// 修复前
static let inputIconBg = Color(UIColor.secondarySystemBackground)   // #F2F2F7
static let inputIconBorder = Color(… light: UIColor(white: 0, alpha: 0) …)  // 完全透明

// 修复后
static let inputIconBg = Color.clear
static let inputIconBorder = Color(… light: UIColor(white: 0.78, alpha: 1) …)
```

透明填充 + 一条看得见的细边，外观与聊天列表的 `↑ ↓` 一致。

**第三步：容器阴影按系统分支区别对待**

- iOS 26+：保留 `glassEffect`（材质自带边缘，别叠手绘阴影）
- iOS < 26：删掉手绘投影，改用 0.5pt 描边维持轮廓

---

## 四、验收

1. 关于页确认 `Version 1.0.254 (46)` 或更高。
2. 聊天页：`+`、`/`、麦克风、发送周围不应出现比按钮更大的方形色块。
3. 消息区右缘：`↑`、`↓` 只有圆形 + 细边。
4. 终端页：`隐藏/粘贴/Esc/Tab` 只有胶囊底色，胶囊外与终端背景同色。
5. 输入区整体：无外扩投影，只有一圈 0.5pt 细边。

---

## 五、待办（尚未覆盖）

| 项 | 文件 | 说明 |
|---|---|---|
| 语音输入面板的 `⌄` / `/` / 发送 / 键盘 | `Views/Chat/Voice/InlineVoiceInputView.swift` | 与 composer 同源，需要在该视图根节点补 `.buttonStyle(.plain)` |
| 「语音输入 · 系统识别（在线）」胶囊 | 同上 | 该胶囊可能由 `Menu`/`Picker` 承载，需单独确认是系统样式还是自绘 |
| 其它同步页残留的语言/图标 | `Views/Settings/*` | 未逐一验收 |

---

## 六、经验

- 编译 SDK 与运行系统不一致时，默认控件样式会在旧系统上退化；只要视图自绘外观，就显式 `buttonStyle(.plain)`。
- 排查「阴影」不要只搜 `.shadow(`：先找同屏内**样式差异最大的那一对按钮**，差异就是根因。
- 融合上游代码后，凡是依赖系统默认样式的控件都要在旧系统上重新验收。

---

## 附：同批修复

| 项 | 文件 | commit |
|---|---|---|
| 移除 OneDrive / WebDAV 的 Coming Soon 占位 | `Views/Sync/OtherSyncSettingsView.swift` | `07e2a63` |
| Deep Mode → 深度模式 | `Views/Settings/SettingsSheet.swift` | `07e2a63` |
| 技能分组（设置页）默认深度技能 / 其他技能 | `Views/Skills/SkillsManagementView.swift` | `0353b10` |
| 技能分组（会话内）分组 + 各组分批开关 | `Views/Chat/SessionSkillsView.swift` | `0353b10` |
| iOS 关于页新增「检查更新」入口 | `Views/Settings/AboutView.swift` | `c329d5a` |
| Android 更新源改指向 vbox-Ai/Lobster-APP | `app/build.gradle.kts` | `462713d` |
