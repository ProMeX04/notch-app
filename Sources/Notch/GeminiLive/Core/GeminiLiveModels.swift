import AppKit
import Foundation
import NotchGeminiLiveCore
import NotchGeminiSkillStorage
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

enum GeminiLiveReconnectState: Equatable {
    case none
    case transport
    case sessionRefresh
    case fullRestart

    var preservesLiveSessionUI: Bool {
        self != .none
    }
}

enum GeminiLiveLifecycleState: Equatable {
    case disconnected
    case connecting
    case live
    case reconnecting(GeminiLiveReconnectState)
    case failed

    var visualConnectionState: GeminiLiveConnectionState {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting, .reconnecting:
            return .connecting
        case .live:
            return .connected
        case .failed:
            return .failed
        }
    }

    /// Including `.connecting` keeps Gemini Talk / floating orb chrome visible while outbound
    /// handshake runs (fresh connect or resumed session awaiting token/socket). Omitting it
    /// briefly hid `JarvisBackgroundWindowController` (`showsConnectedSessionUI` went false).
    var preservesSessionUI: Bool {
        switch self {
        case .live, .reconnecting, .connecting:
            return true
        case .disconnected, .failed:
            return false
        }
    }

    var canDisconnect: Bool {
        switch self {
        case .connecting, .live, .reconnecting:
            return true
        case .disconnected, .failed:
            return false
        }
    }

    var canManageConfiguration: Bool {
        switch self {
        case .disconnected, .failed:
            return true
        case .connecting, .live, .reconnecting:
            return false
        }
    }

    var canSendLiveInput: Bool {
        if case .live = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .reconnecting:
            return true
        case .disconnected, .live, .failed:
            return false
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

struct GeminiLiveModel: Identifiable, Hashable, Codable {
    static let defaultModelID = "gemini-3.1-flash-live-preview"

    let id: String
    let name: String
    let displayName: String
    let supportedGenerationMethods: [String]

    init(
        id: String,
        name: String? = nil,
        displayName: String? = nil,
        supportedGenerationMethods: [String] = []
    ) {
        let normalizedID = GeminiLiveModel.normalizedModelID(id)
        self.id = normalizedID
        self.name = name ?? "models/\(normalizedID)"
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!
            : normalizedID
        self.supportedGenerationMethods = supportedGenerationMethods
    }

    var apiName: String { id }

    static func normalizedModelID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "models/", with: "")
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
    /// When false, does not drive the floating transcript overlay line.
    var showsInOverlay: Bool = true
}

struct SkillWriterApprovalRequest: Identifiable, Equatable, Sendable {
    let toolCallID: String
    let summary: String
    let preview: String

    var id: String { toolCallID }
}

enum SkillWriterToolAction: String, Sendable {
    case create
    case update
}

struct PendingSkillWriterCall: @unchecked Sendable {
    let toolCallID: String
    let args: [String: Any]
    let action: SkillWriterToolAction
    let draft: SkillDraft
    let existingSkillID: String?
}

/// Single snapshot of everything the transcript overlay needs.
/// Derived inside GeminiLiveViewModel so the controller subscribes to one publisher.
struct TranscriptOverlayInput: Equatable {
    var userText: String = ""
    var modelText: String = ""
    var isModelSpeaking: Bool = false
    var toolAction: ToolActionToast? = nil
    var subsEnabled: Bool = true
    var isConnected: Bool = false

    static let idle = TranscriptOverlayInput()

    var hasVisibleContent: Bool {
        (subsEnabled && (!modelText.isEmpty || isModelSpeaking))
            || toolAction != nil
    }

    var shouldShow: Bool { isConnected && hasVisibleContent }

    /// Used to suppress panel re-opening when only transient extras clear.
    var transcriptKey: String { modelText }
}

enum GeminiTool: String, CaseIterable, Identifiable {
    case webSearch = "webSearch"
    case read = "read"
    case calendar = "calendar"
    case clipboard = "clipboard"
    case appControl = "appControl"
    case mediaControl = "mediaControl"
    case pomodoro = "pomodoro"
    case browserControl = "browserControl"
    case localFileSearch = "localFileSearch"
    case memory = "memory"
    case exec = "exec"
    case appleMail = "appleMail"
    case showResult = "showResult"
    case skillWriter = "skillWriter"

    var id: String { rawValue }

    static let coreCases: [GeminiTool] = [
        .webSearch,
        .read,
        .calendar,
        .clipboard,
        .appControl,
        .mediaControl,
        .pomodoro,
        .browserControl,
        .localFileSearch,
        .memory,
        .appleMail,
        .showResult,
    ]

    static let coreToolSet: Set<GeminiTool> = Set(coreCases)
    static let allToolSet: Set<GeminiTool> = coreToolSet.union(restrictedTools)
    static let defaultEnabledCases: [GeminiTool] = [
        .webSearch,
        .read,
        .calendar,
        .clipboard,
        .appControl,
        .mediaControl,
        .pomodoro,
        .browserControl,
        .memory,
        .showResult,
    ]

    /// Tools excluded from the default set for safety.
    /// Shown in the picker but off by default; enabling them requires an explicit warning acknowledgment.
    static let restrictedTools: Set<GeminiTool> = [.exec, .skillWriter]

    var displayName: String {
        switch self {
        case .webSearch: return "Search"
        case .read: return "Read"
        case .calendar: return "Calendar"
        case .clipboard: return "Clipboard"
        case .appControl: return "App"
        case .mediaControl: return "Media"
        case .pomodoro: return "Focus"
        case .browserControl: return "Browser"
        case .localFileSearch: return "Local File Search"
        case .memory: return "Memory"
        case .exec: return "Exec"
        case .appleMail: return "Mail"
        case .showResult: return "Show Result"
        case .skillWriter: return "Skill Writer"
        }
    }

    var icon: String {
        switch self {
        case .webSearch: return "magnifyingglass"
        case .read: return "doc.text"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .appControl: return "macwindow"
        case .mediaControl: return "playpause"
        case .pomodoro: return "timer"
        case .browserControl: return "safari"
        case .localFileSearch: return "doc.text.magnifyingglass"
        case .memory: return "brain"
        case .exec: return "terminal"
        case .appleMail: return "envelope"
        case .showResult: return "tray.full"
        case .skillWriter: return "wand.and.rays.inverse"
        }
    }
}

struct GeminiSystemPromptPreset: Identifiable, Hashable, Codable {
    static let defaultAvatarSymbolName = "sparkles"
    static let availableAvatarSymbolNames = [
        "music.mic",
        "sparkles",
        "books.vertical.fill",
        "person.crop.circle.fill",
        "bubble.left.and.bubble.right.fill",
        "wand.and.stars",
        "bolt.fill",
        "lightbulb.fill",
        "headphones",
        "globe"
    ]
    private static let sharedAvatarStore = GeminiAgentAvatarStore()

    let id: String
    var title: String
    var content: String
    /// rawValues of enabled GeminiTool cases. Empty = no tools enabled.
    var enabledTools: [String]
    /// Installed skill record ids (`SkillRecord.id`) enabled for this preset.
    var enabledSkillIDs: [String]
    /// Legacy per-preset storage by display name — migrated into `enabledSkillIDs` once skills load.
    var enabledSkillNames: [String]
    /// GeminiVoice.rawValue for this preset.
    var voice: String
    /// Gemini Live model id for this preset.
    var model: String
    /// GeminiThinkingLevel.rawValue for this preset.
    var thinkingLevel: String
    /// SF Symbol used as the agent avatar in setup UI.
    var avatarSymbolName: String
    /// Relative filename of a custom avatar image stored in app state.
    var avatarImageFilename: String?
    /// Tracks when the agent was last selected or created to allow sorting by recency.
    var lastUsedAt: Date?

    init(
        id: String,
        title: String,
        content: String,
        enabledTools: [String] = [],
        enabledSkillIDs: [String] = [],
        enabledSkillNames: [String] = [],
        voice: String = GeminiVoice.kore.rawValue,
        model: String = GeminiLiveModel.defaultModelID,
        thinkingLevel: String = GeminiThinkingLevel.off.rawValue,
        avatarSymbolName: String = GeminiSystemPromptPreset.defaultAvatarSymbolName,
        avatarImageFilename: String? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.enabledTools = enabledTools
        self.enabledSkillIDs = enabledSkillIDs
        self.enabledSkillNames = enabledSkillNames
        self.voice = voice
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.avatarSymbolName = avatarSymbolName
        self.avatarImageFilename = avatarImageFilename
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, enabledTools, enabledSkillIDs, enabledSkillNames, voice, model, thinkingLevel, avatarSymbolName, avatarImageFilename, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
        enabledTools = try c.decodeIfPresent([String].self, forKey: .enabledTools) ?? []
        enabledSkillIDs = try c.decodeIfPresent([String].self, forKey: .enabledSkillIDs) ?? []
        enabledSkillNames = try c.decodeIfPresent([String].self, forKey: .enabledSkillNames) ?? []
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? GeminiVoice.kore.rawValue
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? GeminiLiveModel.defaultModelID
        thinkingLevel = try c.decodeIfPresent(String.self, forKey: .thinkingLevel) ?? GeminiThinkingLevel.off.rawValue
        avatarSymbolName = try c.decodeIfPresent(String.self, forKey: .avatarSymbolName) ?? GeminiSystemPromptPreset.defaultAvatarSymbolName
        avatarImageFilename = try c.decodeIfPresent(String.self, forKey: .avatarImageFilename)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(enabledTools, forKey: .enabledTools)
        try c.encode(enabledSkillIDs.sorted(), forKey: .enabledSkillIDs)
        try c.encode(enabledSkillNames, forKey: .enabledSkillNames)
        try c.encode(voice, forKey: .voice)
        try c.encode(model, forKey: .model)
        try c.encode(thinkingLevel, forKey: .thinkingLevel)
        try c.encode(avatarSymbolName, forKey: .avatarSymbolName)
        try c.encodeIfPresent(avatarImageFilename, forKey: .avatarImageFilename)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }

    var toolSet: Set<GeminiTool> {
        Set(enabledTools.compactMap(GeminiTool.init(rawValue:))).intersection(GeminiTool.allToolSet)
    }

    var voiceEnum: GeminiVoice {
        GeminiVoice(rawValue: voice) ?? .kore
    }

    var modelAPIName: String {
        GeminiLiveModel.normalizedModelID(model)
    }

    var thinkingEnum: GeminiThinkingLevel {
        GeminiThinkingLevel(rawValue: thinkingLevel) ?? .off
    }

    var resolvedAvatarSymbolName: String {
        if Self.availableAvatarSymbolNames.contains(avatarSymbolName) {
            return avatarSymbolName
        }
        return Self.defaultAvatarSymbolName
    }

    var hasCustomAvatarImage: Bool {
        !(avatarImageFilename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var resolvedAvatarImageURL: URL? {
        Self.sharedAvatarStore.imageURL(for: avatarImageFilename)
    }

    static let defaultPreset = GeminiSystemPromptPreset(
        id: "default",
        title: "Default",
        content: "",
        enabledTools: GeminiTool.defaultEnabledCases.map(\.rawValue),
        enabledSkillIDs: [SkillRecord.gettingStartedBuiltinID],
        voice: GeminiVoice.kore.rawValue,
        model: GeminiLiveModel.defaultModelID,
        thinkingLevel: GeminiThinkingLevel.high.rawValue
    )

    static let defaultPresets = [defaultPreset]
}
