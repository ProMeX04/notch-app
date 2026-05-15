import SwiftUI

// MARK: - Markdown

struct MarkdownBlock: Identifiable {
    let id: Int
    let content: String
    let isCode: Bool
}

/// How `NotchMarkdownView` participates in horizontal layout (notch transcript vs floating caption bubble).
enum NotchMarkdownWidthMode: Equatable {
    /// Use available width from the parent (default notch panel behavior).
    case fillParent
    /// Grow with text up to `maxWidth` (floating transcript overlay bubble).
    case hugContent(maxWidth: CGFloat)
}

struct NotchMarkdownView: View {
    let text: String
    let isUser: Bool
    var widthMode: NotchMarkdownWidthMode = .fillParent
    @Environment(\.colorScheme) private var colorScheme

    private var isLightChrome: Bool { colorScheme == .light }
    private var proseColor: Color { isLightChrome ? .black.opacity(0.9) : .white.opacity(0.92) }
    private var codeTextColor: Color { isLightChrome ? .black.opacity(0.92) : .white.opacity(0.95) }
    private var codeFillColor: Color { isLightChrome ? .black.opacity(0.06) : .black.opacity(0.4) }
    private var codeStrokeColor: Color { isLightChrome ? .black.opacity(0.12) : .white.opacity(0.1) }

    var body: some View {
        let blocks = parseMarkdown(text)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            ForEach(blocks) { block in
                if block.isCode {
                    codeBlockView(block.content)
                } else {
                    let content = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty || (blocks.count == 1) {
                        proseText(block.content)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func codeBlockView(_ content: String) -> some View {
        let code = VStack(alignment: .leading, spacing: 0) {
            Text(content)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(codeTextColor)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(codeFillColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(codeStrokeColor, lineWidth: 0.5)
        )

        switch widthMode {
        case .fillParent:
            code
        case let .hugContent(maxW):
            code.frame(maxWidth: maxW, alignment: .leading)
        }
    }

    @ViewBuilder
    private func proseText(_ raw: String) -> some View {
        let attributed = buildAttributed(markdown: raw, proseFontSize: 13)
        let textView = Text(attributed)
            .foregroundStyle(proseColor)
            .multilineTextAlignment(isUser ? .trailing : .leading)

        switch widthMode {
        case .fillParent:
            textView.fixedSize(horizontal: false, vertical: true)
        case let .hugContent(maxW):
            textView
                .frame(maxWidth: maxW, alignment: isUser ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buildAttributed(markdown: String, proseFontSize: CGFloat) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        guard var attributed = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }

        let runsSnapshot = Array(attributed.runs)
        for run in runsSnapshot {
            var attrs = AttributeContainer()

            let inlineCode = run.inlinePresentationIntent?.contains(.code) == true
            let blockCode = codeBlockDepth(run.presentationIntent) != nil

            if blockCode || inlineCode {
                attrs.font = .system(size: 12, design: .monospaced)
            } else if let level = headerLevel(run.presentationIntent) {
                let scale: CGFloat = switch level {
                case 1: 1.28
                case 2: 1.18
                default: 1.1
                }
                attrs.font = .system(size: proseFontSize * scale, weight: .semibold)
            } else {
                attrs.font = .system(size: proseFontSize, weight: .medium, design: .rounded)
            }

            attributed[run.range].mergeAttributes(attrs, mergePolicy: .keepNew)
        }

        return attributed
    }

    private func headerLevel(_ intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .header(let level) = component.kind {
                return level
            }
        }
        return nil
    }

    private func codeBlockDepth(_ intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .codeBlock = component.kind {
                return 1
            }
        }
        return nil
    }

    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            var content = part
            if i % 2 == 1 {
                let lines = part.components(separatedBy: .newlines)
                if lines.count > 1, !lines[0].contains(" "), !lines[0].isEmpty {
                    content = lines.dropFirst().joined(separator: "\n")
                }
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !content.isEmpty || parts.count == 1 {
                result.append(MarkdownBlock(id: i, content: content, isCode: i % 2 == 1))
            }
        }
        return result
    }
}

// MARK: - Progressive reveal

struct ProgressiveRevealText: View {
    let text: String
    var animateOnAppear = false

    @State private var displayedText = ""
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        NotchMarkdownView(text: displayedText, isUser: false)
            .textSelection(.enabled)
            .onAppear {
                syncReveal(to: text, animated: animateOnAppear)
            }
            .onChange(of: text) { _, newValue in
                syncReveal(to: newValue, animated: true)
            }
    }

    private func syncReveal(to target: String, animated: Bool) {
        revealTask?.cancel()

        guard animated, !target.isEmpty else {
            displayedText = target
            return
        }

        guard target != displayedText else { return }

        // Trimming the tail (same prefix, shorter target): snap instantly — avoids “slow erase”
        // from clearing then re-typing character-by-character.
        if displayedText.hasPrefix(target), target.count < displayedText.count {
            displayedText = target
            return
        }

        if !target.hasPrefix(displayedText) {
            displayedText = ""
        }

        revealTask = Task { @MainActor in
            while displayedText.count < target.count {
                // Advance multiple characters per tick to reduce SwiftUI body
                // evaluations (~4x fewer re-renders while preserving the
                // typing feel). Pause on punctuation for natural cadence.
                let remaining = target.count - displayedText.count
                let chunkSize = min(remaining, 4)
                let nextIndex = target.index(
                    target.startIndex,
                    offsetBy: displayedText.count + chunkSize,
                    limitedBy: target.endIndex
                ) ?? target.endIndex

                displayedText = String(target[..<nextIndex])
                let lastCharacter = displayedText.last ?? " "
                try? await Task.sleep(for: revealDelay(after: lastCharacter))
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func revealDelay(after character: Character) -> Duration {
        switch character {
        case ".", "!", "?":
            return .milliseconds(45)
        case ",", ";", ":":
            return .milliseconds(28)
        case " ":
            return .milliseconds(8)
        default:
            return .milliseconds(14)
        }
    }
}
