import AppKit
import Foundation

extension GeminiLiveViewModel {
    var effectiveConnectionState: GeminiLiveConnectionState {
        lifecycleState.visualConnectionState
    }

    var showsConnectedSessionUI: Bool {
        lifecycleState.preservesSessionUI
    }

    var canDisconnectSession: Bool {
        lifecycleState.canDisconnect
    }

    var canManageConfiguration: Bool {
        lifecycleState.canManageConfiguration
    }

    var canSendLiveInput: Bool {
        lifecycleState.canSendLiveInput
    }

    var isProUser: Bool {
        entitlementStore.isProUser
    }

    var talkPermissionDecision: NotchPermissionDecision {
        entitlementStore.decision(for: .talkConnection)
    }

    var connectionButtonTitle: String {
        switch effectiveConnectionState {
        case .connected:
            return "Disconnect"
        case .connecting:
            return "Cancel"
        case .disconnected, .failed:
            return "Connect"
        }
    }

    var connectionButtonIcon: String {
        switch effectiveConnectionState {
        case .connected:
            return "xmark.circle.fill"
        case .connecting:
            return "stop.circle.fill"
        case .disconnected, .failed:
            return "play.circle.fill"
        }
    }

    var microphoneButtonTitle: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive ? "Release to Send" : "Hold to Talk"
        }
        return isMicrophoneEnabled ? "Mute Mic" : "Unmute Mic"
    }

    var microphoneButtonIcon: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive ? "mic.circle.fill" : "mic"
        }
        return isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
    }

    var canToggleMicrophone: Bool {
        canDisconnectSession
    }

    var showCompactIndicator: Bool {
        switch effectiveConnectionState {
        case .connecting, .connected:
            return true
        case .failed, .disconnected:
            return false
        }
    }

    var compactAccentColor: NSColor {
        effectiveConnectionState.accentColor
    }

    var isVisualSharingEnabled: Bool { isScreenSharingEnabled || isCameraSharingEnabled }

    var visualSharingLabel: String {
        if isCameraSharingEnabled { return "Camera" }
        if isWindowScreenSharing { return "App" }
        if isRegionScreenSharing { return "Region" }
        return "Screen"
    }

    var visualSharingIcon: String {
        if isCameraSharingEnabled { return "video.fill" }
        if isWindowScreenSharing { return "macwindow" }
        if isRegionScreenSharing { return "crop" }
        return isVisualSharingEnabled ? "eye.fill" : "eye"
    }

    var screenSharingLabel: String { visualSharingLabel }

    var screenSharingIcon: String { visualSharingIcon }

    var isRegionScreenSharing: Bool { isScreenSharingEnabled && screenShareMode == .selectedRegion }

    var isWindowScreenSharing: Bool { isScreenSharingEnabled && screenShareMode == .appWindow }

    var isCompactIndicatorAnimated: Bool {
        isActivelyListening
    }

    var holdToTalkReadyText: String {
        "Hold \(holdToTalkShortcut.displayString) to talk."
    }

    var connectedMicStatusText: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive
                ? (isMicrophoneLive ? "Listening… Release to send." : pendingMicrophoneStatusText)
                : holdToTalkReadyText
        }
        guard isMicrophoneEnabled else { return "Microphone is muted." }
        return isMicrophoneLive ? "Microphone is live." : pendingMicrophoneStatusText
    }

    var pendingMicrophoneStatusText: String {
        "Starting microphone..."
    }

    var effectiveMicrophoneEnabled: Bool {
        switch inputMode {
        case .openMic:
            return isMicrophoneEnabled
        case .pushToTalk:
            return isHoldToTalkActive
        }
    }

    var isActivelyListening: Bool {
        canSendLiveInput && effectiveMicrophoneEnabled && isMicrophoneLive
    }

    var connectedPlaceholderText: String {
        if reconnectState.preservesLiveSessionUI {
            return statusText
        }
        return isActivelyListening ? "Gemini is listening..." : connectedMicStatusText
    }

    var shouldShowMicrophoneReadinessHint: Bool {
        showsConnectedSessionUI && effectiveMicrophoneEnabled && !isMicrophoneLive
    }

    var microphoneReadinessHintText: String {
        if reconnectState.preservesLiveSessionUI {
            return "Microphone will be ready after Gemini reconnects."
        }
        return "Microphone is not ready yet. Wait a moment before talking."
    }

    var microphoneReadinessHintIcon: String {
        reconnectState.preservesLiveSessionUI ? "mic.badge.clock.fill" : "mic.slash.circle.fill"
    }

    var compactMicrophoneReadinessIcon: String {
        reconnectState.preservesLiveSessionUI ? "mic.badge.clock.fill" : "mic.slash.circle.fill"
    }

    var transcriptOverlayMode: TranscriptOverlayMode {
        if !showTranscriptOverlay {
            return .hidden
        }
        return transcriptOverlayAutoHide ? .autoHide : .pinned
    }
}
