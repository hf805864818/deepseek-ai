import SwiftUI
import UIKit

// MARK: - Pending Provider Import

struct PendingProviderImport: Identifiable {
    let id = UUID()
    /// The raw JSON string, fed directly to `importInstanceJSON`.
    let json: String
    /// A temp copy of the file for the "add as attachment" branch (the
    /// shared original is cleaned up right after ingestion).
    let fileURL: URL
}

// MARK: - Scroll To Bottom Background

struct ScrollToBottomBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Color(.systemBackground).opacity(colorScheme == .dark ? 0.8 : 0.92)
    }
}

// MARK: - Input Bar Popup Chrome

/// Shared chrome (background + border + shadow + max-width) for the `/`
/// and `@` popups. Extracted to its own struct so both popup call-sites
/// read identically regardless of which popup is firing, so the
/// pop-from-`/`-button animation reads identically across the two.
struct InputBarPopupChrome<Content: View>: View {
    let maxContentWidth: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor.systemBackground }))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 0.75) : UIColor(white: 0, alpha: 0.12) }), radius: 8, x: 0, y: 4)
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, 12)
    }
}

// MARK: - Mention Row

/// A single row in the file-mention menu.
struct MentionRow: View {
    let entry: FileMentionEntry
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : ChatColors.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.basename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : ChatColors.primaryText)
                    .lineLimit(1)
                Text(entry.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : ChatColors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(entry.mountName ?? entry.scope.displayLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : ChatColors.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        isSelected
                        ? Color.white.opacity(0.2)
                        : Color(UIColor.systemGray5)
                    )
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var iconName: String {
        if entry.isDirectory { return "folder" }
        switch entry.scope {
        case .workspace:   return "doc.text"
        case .attachments: return "paperclip"
        case .shared:      return "folder.badge.person.crop"
        case .skills:      return "sparkles"
        case .memory:      return "brain.head.profile"
        case .mount:       return "externaldrive"
        }
    }
}

// MARK: - Slash Menu Button Style

/// Button style for slash menu items — shows highlight on press.
struct SlashMenuButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((isSelected || configuration.isPressed) ? Color.accentColor : Color.clear)
    }
}

// MARK: - Slash Command Row

/// Single row in the slash command menu.
struct SlashCommandRow: View {
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
            // Label area — tap to toggle thinking on/off and dismiss
            HStack(spacing: 8) {
                Group {
                    if cmd.id == "thinking" {
                        Image("ThinkingIcon")
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: cmd.icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundStyle(rowIconColor)
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    let isThinkingActive = cmd.id == "thinking" && thinkingLevel.isEnabled && thinkingSupported
                    let titleColor: Color = isThinkingActive
                        ? .blue : (cmd.id == "deepmode" ? .purple : (isSelected ? .white : ChatColors.primaryText))
                    let subtitleText = (cmd.id == "thinking" && !thinkingSupported)
                        ? AppLocalized("Not supported by current model")
                        : cmd.subtitle
                    let subtitleColor: Color = (cmd.id == "thinking" && !thinkingSupported)
                        ? .secondary
                        : (isThinkingActive ? .blue.opacity(0.7) : (cmd.id == "deepmode" ? .purple.opacity(0.7) : (isSelected ? .white.opacity(0.7) : ChatColors.secondaryText)))
                    // [T-slash-picker-product-rules] Title + subtitle
                    // each clamped to a single line. Long skill names
                    // and descriptions used to wrap and pump the row
                    // height past 60pt, which then snowballed into a
                    // multi-screen picker.
                    Text("/\(cmd.title.lowercased())")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .allowsHitTesting(cmd.id == "thinking")
            .onTapGesture { onToggleThinking?() }
            if cmd.id == "memory" {
                // [T-ios-voiceover-labels] Status glyph, not a control:
                // give it the on/off meaning in words instead of letting
                // VoiceOver read "checkmark circle fill" / "slash circle".
                Image(systemName: memoryEnabled ? "checkmark.circle.fill" : "slash.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(memoryEnabled ? (isSelected ? .white : .green) : (isSelected ? .white.opacity(0.6) : .secondary))
                    .accessibilityLabel(Text(
                        memoryEnabled
                            ? AppLocalized("Memory on", comment: "VoiceOver label for the memory status icon when enabled")
                            : AppLocalized("Memory off", comment: "VoiceOver label for the memory status icon when disabled")
                    ))
            }
            if cmd.id == "deepmode" {
                deepModeLevelPicker
            }
            if cmd.id == "thinking" && thinkingSupported {
                thinkingLevelPicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowIconColor: Color {
        if cmd.id == "deepmode" {
            return .purple
        }
        guard cmd.id == "thinking" else {
            return isSelected ? .white.opacity(0.8) : ChatColors.secondaryText
        }
        if !thinkingSupported { return .secondary }
        return thinkingLevel.isEnabled ? .blue : (isSelected ? .white.opacity(0.8) : ChatColors.secondaryText)
    }

    // [T-deep-mode-level] Three-tier purple picker for deep mode intensity.
    // Mirrors the thinking-level picker layout but with purple accent
    // to distinguish it from the blue ThinkingLevel picker.
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
                .background(
                    isExactMatch ? Color.purple : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture { onSetDeepModeLevel?(level) }
                .id(level)
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var thinkingLevelPicker: some View {
        let maxAvailable = availableLevels.last
        let isClamped = thinkingLevel.isEnabled && maxAvailable != nil && thinkingLevel > (maxAvailable ?? thinkingLevel)

        return HStack(spacing: 0) {
            ForEach(availableLevels, id: \.self) { level in
                let isExactMatch = thinkingLevel == level
                let isClampedHighlight = isClamped && level == maxAvailable
                let isHighlighted = isExactMatch || isClampedHighlight

                HStack(spacing: 1) {
                    Text(level.displayName)
                        .font(.system(size: 11, weight: isHighlighted ? .bold : .regular))
                    if isClampedHighlight {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(isHighlighted ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isHighlighted
                        ? (isClampedHighlight
                            ? Color.orange.opacity(0.75)
                            : Color.blue)
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture { onSetThinkingLevel?(isHighlighted ? .off : level) }
                .id(level)
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
