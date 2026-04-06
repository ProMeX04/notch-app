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
                .foregroundStyle(.white.opacity(0.95))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
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
        let textView = Text(LocalizedStringKey(raw))
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(isUser ? .trailing : .leading)

        switch widthMode {
        case .fillParent:
            textView.fixedSize(horizontal: false, vertical: true)
        case let .hugContent(maxW):
            // `fixedSize(horizontal: true)` prevents multiline wrap — use max width + vertical growth.
            textView
                .frame(maxWidth: maxW, alignment: isUser ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            var content = part
            if i % 2 == 1 {
                // It's a code block, try to strip language line
                let lines = part.components(separatedBy: .newlines)
                if lines.count > 1, !lines[0].contains(" "), !lines[0].isEmpty {
                    content = lines.dropFirst().joined(separator: "\n")
                }
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Add block
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
                let nextIndex = target.index(
                    target.startIndex,
                    offsetBy: displayedText.count + 1,
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
