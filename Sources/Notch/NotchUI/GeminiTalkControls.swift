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
struct GeminiTranscriptModeToggle: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var mode: GeminiLiveViewModel.TranscriptOverlayMode {
        gemini.transcriptOverlayMode
    }

    private var icon: String {
        "captions.bubble"
    }

    private var label: String {
        switch mode {
        case .autoHide:
            return Localization.get("Auto Hide", lang: appLanguage)
        case .pinned:
            return Localization.get("Pin", lang: appLanguage)
        case .hidden:
            return Localization.get("Off", lang: appLanguage)
        }
    }

    private var isActive: Bool {
        mode != .hidden
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: icon, label: label, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                transcriptRow(Localization.get("Auto Hide", lang: appLanguage)) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = true
                    isPickerOpen = false
                }
                transcriptRow(Localization.get("Pin", lang: appLanguage)) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = false
                    isPickerOpen = false
                }
                Divider()
                    .padding(.vertical, 4)
                transcriptRow(Localization.get("Off", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                    gemini.setTranscriptOverlayEnabled(false)
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

    private func transcriptRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
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
struct GeminiScreenShareMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var isActive: Bool { gemini.isScreenSharingEnabled }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: gemini.screenSharingIcon, label: gemini.screenSharingLabel, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                screenShareRow(Localization.get("Share Full Screen", lang: appLanguage)) {
                    gemini.startFullScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow(Localization.get("Share Selected Region", lang: appLanguage)) {
                    gemini.startRegionScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow(Localization.get("Share App Window", lang: appLanguage)) {
                    gemini.startWindowSharing()
                    isPickerOpen = false
                }
                if gemini.isScreenSharingEnabled {
                    Divider()
                        .padding(.vertical, 4)
                    screenShareRow(Localization.get("Stop Sharing", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                        gemini.stopScreenSharing()
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

    private func screenShareRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
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
