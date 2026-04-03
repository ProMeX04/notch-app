import AppKit
import Combine
import Foundation
import SwiftUI

enum GeminiLiveConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed

    var title: String {
        switch self {
        case .disconnected:
            return "Offline"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Live"
        case .failed:
            return "Error"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .disconnected:
            return .systemGray
        case .connecting:
            return .systemOrange
        case .connected:
            return .systemGreen
        case .failed:
            return .systemRed
        }
    }
}

enum GeminiThinkingLevel: String, CaseIterable {
    case off = "Off"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var budget: Int {
        switch self {
        case .off: return 0
        case .low: return 512
        case .medium: return 2048
        case .high: return 8192
        }
    }
}

enum GeminiVoice: String, CaseIterable {
    // Standard Live API voices (original 8)
    case aoede = "Aoede"
    case charon = "Charon"
    case fenrir = "Fenrir"
    case kore = "Kore"
    case leda = "Leda"
    case orus = "Orus"
    case puck = "Puck"
    case zephyr = "Zephyr"
    // Extended TTS/Native voices
    case achernar = "Achernar"
    case achird = "Achird"
    case algenib = "Algenib"
    case algieba = "Algieba"
    case alnilam = "Alnilam"
    case autonoe = "Autonoe"
    case callirrhoe = "Callirrhoe"
    case despina = "Despina"
    case enceladus = "Enceladus"
    case erinome = "Erinome"
    case gacrux = "Gacrux"
    case iapetus = "Iapetus"
    case laomedeia = "Laomedeia"
    case pulcherrima = "Pulcherrima"
    case rasalgethi = "Rasalgethi"
    case rasalhague = "Rasalhague"
    case sadachbia = "Sadachbia"
    case sadaltager = "Sadaltager"
    case schedar = "Schedar"
    case sulafar = "Sulafar"
    case umbriel = "Umbriel"
    case vindemiatrix = "Vindemiatrix"
    case zubenelgenubi = "Zubenelgenubi"

    var apiName: String { rawValue }
}

struct ToolActionToast: Equatable {
    let label: String
    let icon: String
}

struct ImageOverlayRequest: Identifiable, Equatable {
    let id = UUID()
    let query: String
    let imageURL: URL
    let sourceURL: URL?
    let caption: String
    let photographer: String?
}

/// Single snapshot of everything the transcript overlay needs.
/// Derived inside GeminiLiveViewModel so the controller subscribes to one publisher.
struct TranscriptOverlayInput: Equatable {
    var userText: String = ""
    var modelText: String = ""
    var isModelSpeaking: Bool = false
    var toolAction: ToolActionToast? = nil
    var imageRequest: ImageOverlayRequest? = nil
    var subsEnabled: Bool = true
    var isConnected: Bool = false

    static let idle = TranscriptOverlayInput()

    var hasVisibleContent: Bool {
        (subsEnabled && (!userText.isEmpty || !modelText.isEmpty))
            || toolAction != nil || imageRequest != nil
    }

    var shouldShow: Bool { isConnected && hasVisibleContent }

    /// Used to suppress panel re-opening when only extras (image/toast) clear.
    var transcriptKey: String { userText + "\u{1F}" + modelText }
}

enum GeminiTool: String, CaseIterable, Identifiable {
    case controlApp = "controlApp"
    case controlBrowser = "controlBrowser"
    case controlTimer = "controlTimer"
    case controlMedia = "controlMedia"
    case readClipboard = "readClipboard"
    case manageNotes = "manageNotes"
    case controlVolume = "controlVolume"
    case displayImage = "displayImage"
    case webSearch = "webSearch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlApp: return "App"
        case .controlBrowser: return "Browser"
        case .controlTimer: return "Timer"
        case .controlMedia: return "Media"
        case .readClipboard: return "Clipboard"
        case .manageNotes: return "Notes"
        case .controlVolume: return "Volume"
        case .displayImage: return "Images"
        case .webSearch: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .controlApp: return "macwindow"
        case .controlBrowser: return "safari"
        case .controlTimer: return "timer"
        case .controlMedia: return "playpause"
        case .readClipboard: return "doc.on.clipboard"
        case .manageNotes: return "square.and.pencil"
        case .controlVolume: return "speaker.wave.3"
        case .displayImage: return "photo.on.rectangle"
        case .webSearch: return "magnifyingglass"
        }
    }
}

struct GeminiSystemPromptPreset: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var content: String
    /// rawValues of enabled GeminiTool cases. Empty = no tools enabled.
    var enabledTools: [String]
    /// GeminiVoice.rawValue for this preset.
    var voice: String
    /// GeminiThinkingLevel.rawValue for this preset.
    var thinkingLevel: String

    init(
        id: String,
        title: String,
        content: String,
        enabledTools: [String] = [],
        voice: String = GeminiVoice.kore.rawValue,
        thinkingLevel: String = GeminiThinkingLevel.off.rawValue
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.enabledTools = enabledTools
        self.voice = voice
        self.thinkingLevel = thinkingLevel
    }

    var toolSet: Set<GeminiTool> {
        Set(enabledTools.compactMap(GeminiTool.init(rawValue:)))
    }

    var voiceEnum: GeminiVoice {
        GeminiVoice(rawValue: voice) ?? .kore
    }

    var thinkingEnum: GeminiThinkingLevel {
        GeminiThinkingLevel(rawValue: thinkingLevel) ?? .off
    }

    static let defaultPreset = GeminiSystemPromptPreset(
        id: "default",
        title: "Default",
        content: """
        You are Hieu's assistant.

        Communication style:
        - Be cute, friendly, natural, and brief.
        - Hieu speaks to you in English, so respond in English unless he clearly asks for another language.
        """,
        enabledTools: GeminiTool.allCases.map(\.rawValue),
        voice: GeminiVoice.kore.rawValue,
        thinkingLevel: GeminiThinkingLevel.off.rawValue
    )

    static let defaultPresets = [defaultPreset]
}
