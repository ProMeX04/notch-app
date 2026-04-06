import AppKit
import Combine
import Foundation
import SwiftUI

/// Floating panel mode for API keys (Gemini / Pexels / Brave) — shown outside the notch.
enum GeminiSecretsPanelMode: Equatable {
    case geminiOnly
    case allServiceKeys
}

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
    /// When false, only drives the menu bar chip — not the floating transcript overlay line.
    var showsInOverlay: Bool = true
}

struct ExecApprovalRequest: Identifiable, Equatable, Sendable {
    let toolCallID: String
    let command: String
    let workingDirectory: String?
    let timeoutSeconds: Double

    var id: String { toolCallID }
    var commandFamily: String? { execCommandFamily(for: command) }
}

func execCommandFamily(for command: String) -> String? {
    let tokens = shellStyleTokens(from: command, maxTokens: 12)
    guard !tokens.isEmpty else { return nil }

    var index = 0
    if tokens[index] == "env" {
        index += 1
    }

    while index < tokens.count, isShellEnvAssignment(tokens[index]) {
        index += 1
    }

    guard index < tokens.count else { return nil }
    let executable = tokens[index]
    let basename = URL(fileURLWithPath: executable).lastPathComponent
    let trimmed = basename.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed.lowercased()
}

private func isShellEnvAssignment(_ token: String) -> Bool {
    guard let equalIndex = token.firstIndex(of: "="), equalIndex != token.startIndex else { return false }
    let name = token[..<equalIndex]
    guard let first = name.first, first == "_" || first.isLetter else { return false }
    return name.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
}

private func shellStyleTokens(from raw: String, maxTokens: Int) -> [String] {
    let characters = Array(raw)
    var tokens: [String] = []
    var current = ""
    var index = 0
    var quote: Character?

    while index < characters.count {
        let character = characters[index]

        if let quote {
            if character == quote {
                selfConsumingAdvance(&index)
                selfAppendIfNeeded()
                continue
            }
            if character == "\\", quote == "\"", index + 1 < characters.count {
                current.append(characters[index + 1])
                index += 2
                continue
            }
            current.append(character)
            index += 1
            continue
        }

        if character.isWhitespace {
            if !current.isEmpty {
                tokens.append(current)
                if tokens.count >= maxTokens { return tokens }
                current.removeAll(keepingCapacity: true)
            }
            index += 1
            continue
        }

        if character == "'" || character == "\"" {
            quote = character
            index += 1
            continue
        }

        if character == "\\", index + 1 < characters.count {
            current.append(characters[index + 1])
            index += 2
            continue
        }

        current.append(character)
        index += 1
    }

    if !current.isEmpty, tokens.count < maxTokens {
        tokens.append(current)
    }
    return tokens

    func selfConsumingAdvance(_ index: inout Int) {
        quote = nil
        index += 1
    }

    func selfAppendIfNeeded() {
        // Intentionally empty. Closing a quote only changes parser state.
    }
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
        (subsEnabled && (!modelText.isEmpty || isModelSpeaking))
            || toolAction != nil || imageRequest != nil
    }

    var shouldShow: Bool { imageRequest != nil || (isConnected && hasVisibleContent) }

    /// Used to suppress panel re-opening when only extras (image/toast) clear.
    var transcriptKey: String { modelText }
}

enum GeminiTool: String, CaseIterable, Identifiable {
    case webSearch = "webSearch"
    case read = "read"
    case write = "write"
    case exec = "exec"
    case find = "find"
    case grep = "grep"
    case edit = "edit"

    var id: String { rawValue }

    static let coreCases: [GeminiTool] = [
        .webSearch,
        .read,
        .write,
        .exec,
        .find,
        .grep,
        .edit,
    ]

    static let coreToolSet: Set<GeminiTool> = Set(coreCases)

    var displayName: String {
        switch self {
        case .webSearch: return "Search"
        case .read: return "Read"
        case .write: return "Write"
        case .find: return "Find"
        case .grep: return "Grep"
        case .edit: return "Edit"
        case .exec: return "Exec"
        }
    }

    var icon: String {
        switch self {
        case .webSearch: return "magnifyingglass"
        case .read: return "doc.text"
        case .write: return "square.and.pencil"
        case .find: return "folder"
        case .grep: return "text.magnifyingglass"
        case .edit: return "slider.horizontal.below.rectangle"
        case .exec: return "terminal"
        }
    }
}

struct GeminiSystemPromptPreset: Identifiable, Hashable, Codable {
    static let defaultAvatarSymbolName = "waveform"
    static let availableAvatarSymbolNames = [
        "waveform",
        "sparkles",
        "brain.head.profile",
        "person.crop.circle.fill",
        "bubble.left.and.bubble.right.fill",
        "wand.and.stars",
        "bolt.fill",
        "lightbulb.fill",
        "headphones",
        "globe"
    ]

    let id: String
    var title: String
    var content: String
    /// rawValues of enabled GeminiTool cases. Empty = no tools enabled.
    var enabledTools: [String]
    /// Installed skill names enabled for this preset (same idea as `enabledTools`).
    var enabledSkillNames: [String]
    /// GeminiVoice.rawValue for this preset.
    var voice: String
    /// GeminiThinkingLevel.rawValue for this preset.
    var thinkingLevel: String
    /// SF Symbol used as the agent avatar in setup UI.
    var avatarSymbolName: String
    /// Relative filename of a custom avatar image stored in app state.
    var avatarImageFilename: String?

    init(
        id: String,
        title: String,
        content: String,
        enabledTools: [String] = [],
        enabledSkillNames: [String] = [],
        voice: String = GeminiVoice.kore.rawValue,
        thinkingLevel: String = GeminiThinkingLevel.off.rawValue,
        avatarSymbolName: String = GeminiSystemPromptPreset.defaultAvatarSymbolName,
        avatarImageFilename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.enabledTools = enabledTools
        self.enabledSkillNames = enabledSkillNames
        self.voice = voice
        self.thinkingLevel = thinkingLevel
        self.avatarSymbolName = avatarSymbolName
        self.avatarImageFilename = avatarImageFilename
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, enabledTools, enabledSkillNames, voice, thinkingLevel, avatarSymbolName, avatarImageFilename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
        enabledTools = try c.decodeIfPresent([String].self, forKey: .enabledTools) ?? []
        enabledSkillNames = try c.decodeIfPresent([String].self, forKey: .enabledSkillNames) ?? []
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? GeminiVoice.kore.rawValue
        thinkingLevel = try c.decodeIfPresent(String.self, forKey: .thinkingLevel) ?? GeminiThinkingLevel.off.rawValue
        avatarSymbolName = try c.decodeIfPresent(String.self, forKey: .avatarSymbolName) ?? GeminiSystemPromptPreset.defaultAvatarSymbolName
        avatarImageFilename = try c.decodeIfPresent(String.self, forKey: .avatarImageFilename)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(enabledTools, forKey: .enabledTools)
        try c.encode(enabledSkillNames, forKey: .enabledSkillNames)
        try c.encode(voice, forKey: .voice)
        try c.encode(thinkingLevel, forKey: .thinkingLevel)
        try c.encode(avatarSymbolName, forKey: .avatarSymbolName)
        try c.encodeIfPresent(avatarImageFilename, forKey: .avatarImageFilename)
    }

    var toolSet: Set<GeminiTool> {
        Set(enabledTools.compactMap(GeminiTool.init(rawValue:))).intersection(GeminiTool.coreToolSet)
    }

    var voiceEnum: GeminiVoice {
        GeminiVoice(rawValue: voice) ?? .kore
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
        GeminiAgentAvatarStore().imageURL(for: avatarImageFilename)
    }

    static let defaultPreset = GeminiSystemPromptPreset(
        id: "default",
        title: "Default",
        content: "",
        enabledTools: GeminiTool.coreCases.map(\.rawValue),
        voice: GeminiVoice.kore.rawValue,
        thinkingLevel: GeminiThinkingLevel.off.rawValue
    )

    static let defaultPresets = [defaultPreset]
}
