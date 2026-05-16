import SwiftUI

// MARK: - Markdown

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

    var body: some View {
        NativeMarkdownRenderer(
            text: text,
            isUser: isUser,
            widthMode: widthMode,
            style: .notch(colorScheme: colorScheme)
        )
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
