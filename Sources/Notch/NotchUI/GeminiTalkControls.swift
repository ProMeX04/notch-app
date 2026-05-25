import AppKit
import SwiftUI

enum GeminiPanelControlPalette {
    static let liveInactiveFill = Color.white.opacity(0.08)
    static let liveInactiveStroke = Color.white.opacity(0.08)
}
private struct GeminiControlPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var activeTint: Color {
        isDestructive ? Color(nsColor: .systemRed) : themedNotchAccentColor(from: accentColorID)
    }

    private var foregroundColor: Color {
        if isDestructive {
            return .white.opacity(0.96)
        }
        return isActive ? .black.opacity(0.84) : .white.opacity(0.78)
    }

    private var backgroundFill: Color {
        isActive ? activeTint : GeminiPanelControlPalette.liveInactiveFill
    }

    private var shadowColor: Color {
        isActive ? .black.opacity(0.12) : .clear
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(NotchPanelFieldMetrics.labelFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)
            Text(label)
                .font(NotchPanelFieldMetrics.labelFont)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
        .background(
            Capsule()
                .fill(backgroundFill)
                .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
        )
        .overlay {
            if !isActive {
                Capsule()
                    .stroke(GeminiPanelControlPalette.liveInactiveStroke, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}
struct GeminiControlToggle: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeminiControlPill(icon: icon, label: label, isActive: isActive, isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
    }
}
struct GeminiSuggestionMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var mode: GeminiLiveViewModel.TranscriptOverlayMode {
        gemini.transcriptOverlayMode
    }

    private var isActive: Bool {
        gemini.showLiveChatInput || mode != .hidden
    }

    private var label: String {
        if gemini.liveChatInputDisplayMode != .hidden && mode != .hidden {
            return Localization.get("Suggest", lang: appLanguage)
        }
        if gemini.liveChatInputDisplayMode != .hidden {
            switch gemini.liveChatInputDisplayMode {
            case .autoCollapse:
                return Localization.get("Auto Type", lang: appLanguage)
            case .alwaysVisible:
                return Localization.get("Type", lang: appLanguage)
            case .hidden:
                return Localization.get("Suggest", lang: appLanguage)
            }
        }
        switch mode {
        case .autoHide:
            return Localization.get("Auto Hide", lang: appLanguage)
        case .pinned:
            return Localization.get("Pin", lang: appLanguage)
        case .hidden:
            return Localization.get("Suggest", lang: appLanguage)
        }
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: "sparkles", label: label, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                suggestionToggleRow(
                    title: Localization.get("Auto Collapse Type", lang: appLanguage),
                    icon: gemini.liveChatInputDisplayMode == .autoCollapse ? "checkmark.circle.fill" : "circle",
                    isActive: gemini.liveChatInputDisplayMode == .autoCollapse
                ) {
                    gemini.liveChatInputDisplayMode = .autoCollapse
                }
                suggestionToggleRow(
                    title: Localization.get("Always Show Type", lang: appLanguage),
                    icon: gemini.liveChatInputDisplayMode == .alwaysVisible ? "checkmark.circle.fill" : "circle",
                    isActive: gemini.liveChatInputDisplayMode == .alwaysVisible
                ) {
                    gemini.liveChatInputDisplayMode = .alwaysVisible
                }
                suggestionToggleRow(
                    title: Localization.get("Hide Type", lang: appLanguage),
                    icon: gemini.liveChatInputDisplayMode == .hidden ? "checkmark.circle.fill" : "circle",
                    isActive: gemini.liveChatInputDisplayMode == .hidden,
                    foreground: Color(nsColor: .systemRed)
                ) {
                    gemini.liveChatInputDisplayMode = .hidden
                }
                Divider()
                    .padding(.vertical, 4)
                suggestionToggleRow(
                    title: Localization.get("Auto Hide Captions", lang: appLanguage),
                    icon: mode == .autoHide ? "checkmark.circle.fill" : "circle",
                    isActive: mode == .autoHide
                ) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = true
                    isPickerOpen = false
                }
                suggestionToggleRow(
                    title: Localization.get("Pin Captions", lang: appLanguage),
                    icon: mode == .pinned ? "checkmark.circle.fill" : "circle",
                    isActive: mode == .pinned
                ) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = false
                    isPickerOpen = false
                }
                suggestionToggleRow(
                    title: Localization.get("Hide Captions", lang: appLanguage),
                    icon: mode == .hidden ? "checkmark.circle.fill" : "circle",
                    isActive: mode == .hidden,
                    foreground: Color(nsColor: .systemRed)
                ) {
                    gemini.setTranscriptOverlayEnabled(false)
                    isPickerOpen = false
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 210)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func suggestionToggleRow(
        title: String,
        icon: String,
        isActive: Bool,
        foreground: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? themedNotchAccentColor(from: accentColorID) : .secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(foreground)
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
struct GeminiInputModeMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var icon: String {
        switch gemini.inputMode {
        case .openMic:
            return "mic.fill"
        case .pushToTalk:
            return "hand.tap.fill"
        }
    }

    private var title: String {
        switch gemini.inputMode {
        case .openMic:
            return Localization.get("Mic", lang: appLanguage)
        case .pushToTalk:
            if gemini.canDisconnectSession {
                return gemini.holdToTalkShortcut.displayString
            }
            return Localization.get("Push to Talk", lang: appLanguage)
        }
    }

    private var isActive: Bool {
        switch gemini.inputMode {
        case .openMic:
            return gemini.isMicrophoneEnabled
        case .pushToTalk:
            return true
        }
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: icon, label: title, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                inputModeRow(Localization.get("Open Mic", lang: appLanguage)) {
                    gemini.setInputMode(.openMic)
                    gemini.setOpenMicrophoneEnabled(true)
                    isPickerOpen = false
                }
                inputModeRow(Localization.get("Push to Talk", lang: appLanguage)) {
                    gemini.setInputMode(.pushToTalk)
                    isPickerOpen = false
                }
                Divider()
                    .padding(.vertical, 4)
                inputModeRow(Localization.get("Mute Mic", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                    gemini.setInputMode(.openMic)
                    gemini.setOpenMicrophoneEnabled(false)
                    isPickerOpen = false
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func inputModeRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
struct GeminiVisualShareMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var isActive: Bool { gemini.isVisualSharingEnabled }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: gemini.visualSharingIcon, label: Localization.get(gemini.visualSharingLabel, lang: appLanguage), isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                visualShareRow(Localization.get("Share Full Screen", lang: appLanguage)) {
                    gemini.startFullScreenSharing()
                    isPickerOpen = false
                }
                visualShareRow(Localization.get("Share Selected Region", lang: appLanguage)) {
                    gemini.startRegionScreenSharing()
                    isPickerOpen = false
                }
                visualShareRow(Localization.get("Share App Window", lang: appLanguage)) {
                    gemini.startWindowSharing()
                    isPickerOpen = false
                }
                visualShareRow(Localization.get("Share Camera", lang: appLanguage)) {
                    gemini.startCameraSharing()
                    isPickerOpen = false
                }
                if gemini.isVisualSharingEnabled {
                    Divider()
                        .padding(.vertical, 4)
                    visualShareRow(Localization.get("Stop Sharing", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                        gemini.stopVisualSharing()
                        isPickerOpen = false
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 200)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func visualShareRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
struct GeminiOutputVolumeControl: View {
    @Binding var value: Double

    private var icon: String {
        if value <= 0.001 {
            return "speaker.slash.fill"
        }
        if value < 0.34 {
            return "speaker.1.fill"
        }
        if value < 0.67 {
            return "speaker.2.fill"
        }
        return "speaker.3.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(NotchPanelFieldMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)

            Slider(value: $value, in: 0...1)
                .controlSize(.small)
                .tint(.white.opacity(0.9))
                .frame(width: 72)
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
        .background(
            Capsule()
                .fill(GeminiPanelControlPalette.liveInactiveFill)
        )
        .overlay {
            Capsule()
                .stroke(GeminiPanelControlPalette.liveInactiveStroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}
