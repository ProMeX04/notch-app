import Foundation

public struct ExecApprovalRequest: Identifiable, Equatable, Sendable {
    public let toolCallID: String
    public let command: String
    public let workingDirectory: String?
    public let timeoutSeconds: Double

    public init(toolCallID: String, command: String, workingDirectory: String?, timeoutSeconds: Double) {
        self.toolCallID = toolCallID
        self.command = command
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
    }

    public var id: String { toolCallID }
    public var commandFamily: String? { execCommandFamily(for: command) }
}

public struct ExecApprovalActions: Sendable {
    public let isApproved: @Sendable (_ command: String, _ workingDirectory: String?) -> Bool
    public let approveExact: @Sendable (_ command: String, _ workingDirectory: String?) -> Void
    public let approveFamily: @Sendable (_ command: String, _ workingDirectory: String?) -> Void

    public init(
        isApproved: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Bool,
        approveExact: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Void,
        approveFamily: @escaping @Sendable (_ command: String, _ workingDirectory: String?) -> Void
    ) {
        self.isApproved = isApproved
        self.approveExact = approveExact
        self.approveFamily = approveFamily
    }
}

@MainActor
public final class ExecApprovalState: ObservableObject {
    @Published public private(set) var pending: [ExecApprovalRequest] = []

    private let actions: ExecApprovalActions

    public init(actions: ExecApprovalActions) {
        self.actions = actions
    }

    public func enqueue(_ request: ExecApprovalRequest) {
        guard !pending.contains(where: { $0.toolCallID == request.toolCallID }) else { return }
        pending.append(request)
    }

    public func clearAll() {
        pending.removeAll()
    }

    public func approveCurrentOnce() -> String? {
        guard let request = pending.first else { return nil }
        pending.removeAll { $0.toolCallID == request.toolCallID }
        return request.toolCallID
    }

    public func approveCurrentAlwaysExact() -> String? {
        guard let request = pending.first else { return nil }
        actions.approveExact(request.command, request.workingDirectory)
        pending.removeAll { $0.toolCallID == request.toolCallID }
        return request.toolCallID
    }

    public func approveCurrentAlwaysFamily() -> String? {
        guard let request = pending.first else { return nil }
        actions.approveFamily(request.command, request.workingDirectory)
        pending.removeAll { $0.toolCallID == request.toolCallID }
        return request.toolCallID
    }

    public func denyCurrent() -> String? {
        guard let request = pending.first else { return nil }
        pending.removeAll { $0.toolCallID == request.toolCallID }
        return request.toolCallID
    }

    public nonisolated func shouldAutoApprove(command: String, workingDirectory: String?) -> Bool {
        actions.isApproved(command, workingDirectory)
    }
}

public func execCommandFamily(for command: String) -> String? {
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
    }
}
