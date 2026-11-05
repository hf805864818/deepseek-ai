# 按钮「阴影」问题：根因与修复记录

> 适用版本：LobsterAi（`hf805864818/deepseek-ai`）1.0.245 起
> 影响面：iOS 17 设备（用 iOS 26 SDK 编译、跑在旧系统上）

## 一、现象

聊天界面与终端界面的圆形/胶囊形功能按钮，周围出现一圈**灰色圆角方块**，视觉上像阴影或重影。受影响的按钮：

| 界面 | 按钮 | 表现 |
|---|---|---|
| 聊天输入区 | `+`（附件）、`/`（斜杠命令）、麦克风、发送 | 圆/胶囊外多出一块灰底 |
| 聊天消息区 | 翻滚 `↑`（回顶）、`↓`（回底） | 灰方块 + 白圆 |
| 语音输入面板 | 左上 `⌄`（收起）、`/`、发送、语言/键盘按钮 | 灰方块 + 白圆 |
| 语音输入面板 | 「语音输入 · 系统识别（在线）」胶囊 | 胶囊外一圈灰底 |
| 终端 Minis Shell | `隐藏`、`粘贴`、`Esc`、`Tab` | 深色底上多出一块浅灰底板 |

## 二、根因（两层，彼此独立）

### 1. 系统默认 Button 样式画了底板

这个 App 用 **iOS 26 SDK** 编译，但运行在 **iOS 17**。SwiftUI 的 `Button` 默认样式（`.automatic`）由 SDK 决定：iOS 26 SDK 下它会在 label 背后铺一层灰色圆角矩形（在 iOS 26 上是 Liquid Glass 的一部分，在 iOS 17 上退化成一块实心灰底）。

自己画的圆（`Circle()` + 0.5pt 描边）当然盖不住这层底板，于是变成「灰方块 + 白圆」的叠影。

**直接证据**（同一屏内的对照）：

| 按钮 | 代码 |
|---|---|
| 静音「朗…」 | 有 `.buttonStyle(.plain)` → **无底板** |
| `+`、`/`、发送、`↑`、`↓` | 没有 `buttonStyle` → **有底板** |

### 2. 输入区容器在 iOS < 26 上有两条投影

`ComposerSurface` 的两个分支：

```swift
if #available(iOS 26.0, *) {
    content.glassEffect(.regular, in: shape)        // 26+：玻璃自带边缘
} else {
    content
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)                       // 下投影
        .shadow(color: … dark ? .black.opacity(0.5) : .clear …, radius: 8, y: -4)   // 暗色上投影
}
```

iOS 17 走 `else`，整条输入区挂着一圈投影，视觉上与按钮的灰底叠加，加重了「阴影」的感觉。

## 三、修复清单

| # | 文件 | 改动 | 覆盖的按钮 |
|---|---|---|---|
| 1 | `src/ios/Views/Chat/AIChatView/Composer/ComposerSurface.swift` | 删除 `else` 分支的两条 `.shadow`，改为 `.overlay(shape.stroke(ChatColors.inputBorder.opacity(0.6), lineWidth: 0.5))` | 整条输入区（去掉容器投影） |
| 2 | `src/ios/Views/Chat/AIChatView/Support/ChatColors.swift` | `inputIconBg`：`secondarySystemBackground` → `Color.clear`；`inputIconBorder` 浅色 alpha `0` → `0.78` 灰 | `+`、`/`、麦克风、语言徽标、语音面板圆形按钮 |
| 3 | `src/ios/Views/Chat/AIChatView/AIChatView+InputBar.swift` | 输入栏根节点加 `.buttonStyle(.plain)`（在 `.modifier(ComposerSurface())` 之前） | `+`、`/`、麦克风、发送（整行一次覆盖） |
| 4 | `src/ios/Views/Chat/AIChatView/AIChatView+MessagesArea.swift` | 两个滚动按钮各加 `.buttonStyle(.plain)` | 翻滚 `↑` / `↓` |
| 5 | `src/ios/Views/Rootfs/ISHTerminalView.swift` | `QuickCommandButton` 的 `Button` 加 `.buttonStyle(.plain)` | 终端 `隐藏`、`粘贴`、`Esc`、`Tab`、方向键、`Ctrl` 等全部快捷键 |
| 6 | `src/ios/Views/Settings/AboutView.swift` | 新增「更新」区块，接上原本未被引用的 `UpdateChecker` | （顺带修复：iOS 端此前没有任何检查更新入口） |

### 为什么这样改

- **`.buttonStyle(.plain)`**：把背景交还给视图自己。按钮内部本来就有 `Circle()` + 描边，去掉系统底板后只剩自己画的那一层。
- **`inputIconBg` 改透明**：彻底消除「灰底」，让 `composer` 的白底直接透出，只保留 0.78 的细边——与聊天列表那两个 `↑ ↓` 按钮的观感一致。
- **删容器投影**：iOS 26 的玻璃分支不需要手绘阴影（材质自带），iOS 17 分支也不再需要；保留 0.5pt 细边维持轮廓。

## 四、修复前后对照

| 位置 | 修复前 | 修复后 |
|---|---|---|
| 输入区 `+` / `/` | 浅灰圆 + 灰方块底 | 透明填充 + 0.78 细边 |
| 发送按钮 | 灰方块 + 灰圆 | 透明 + 细边（禁用态仍用 `quaternaryLabel` 圆点） |
| 翻滚 `↑ ↓` | 灰方块 + 白圆 | 白圆 + 0.35 灰边，无底板 |
| 终端快捷键 | 浅灰底板 | 只有 `Color(white: 0.25)` 胶囊 + 绿字 |
| 输入区整体 | 一圈向下投影 | 0.5pt 细边，无投影 |

## 五、验证方法

1. 关于页确认版本号包含本轮修复（`1.0.251` 起）。
2. 聊天页：`+`、`/`、麦克风、发送的圆形周围不应再出现比圆更大的方形色块。
3. 消息区右缘滚动按钮：只有圆形 + 细边。
4. 终端页：`隐藏/粘贴/Esc/Tab` 只有胶囊底色，胶囊外应与终端背景同色。

## 六、经验

- **编译 SDK 与运行系统不一致时，默认控件样式会在旧系统上退化。** 只要视图自绘外观，就应显式 `buttonStyle(.plain)`，不要依赖系统默认。
- 排查这类「阴影」不要只搜 `.shadow(`：先看同屏内**样式差异最大的那一对按钮**，差异往往就是根因。
- 融合上游代码后，上游依赖新系统特性的 UI 需要在旧系统上逐一验收，尤其是依赖默认样式的控件。

---

## 附：本轮同批修复的其他项

| 项 | 文件 | 说明 |
|---|---|---|
| 移除 OneDrive / WebDAV 占位 | `Views/Sync/OtherSyncSettingsView.swift` | 两个 `Coming Soon` 行已删除，列表只剩 Local Sync / Google Drive / Backup & Restore |
| Deep Mode 中文化 | `Views/Settings/SettingsSheet.swift` | `AppLocalized("Deep Mode")` → `AppLocalized("深度模式")` |
| 技能分组（设置页） | `Views/Skills/SkillsManagementView.swift` | 分组标题改为「默认深度技能」/「其他技能」 |
| 技能分组（会话内） | `Views/Chat/SessionSkillsView.swift` | 原来一行平铺全部技能，现按来源分两组，各自带独立的批量开关 |
