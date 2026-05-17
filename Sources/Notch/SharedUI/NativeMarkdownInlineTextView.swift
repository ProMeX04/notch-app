import AppKit
import SwiftUI

struct NativeMarkdownInlineTextView: NSViewRepresentable {
    let inlines: [NativeMarkdownInline]
    let style: NativeMarkdownStyle
    var isUser: Bool = false
    var maxWidth: CGFloat = .infinity

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(style: style, colorScheme: colorScheme, maxWidth: maxWidth)
    }

    func makeNSView(context: Context) -> IntrinsicTextView {
        let textView = IntrinsicTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: context.coordinator.maxWidth,
            height: .greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        textView.frame.size.width = context.coordinator.maxWidth
        let attrString = context.coordinator.buildAttributedString(inlines)
        textView.textStorage?.setAttributedString(attrString)
        textView.invalidateIntrinsicContentSize()

        return textView
    }

    func updateNSView(_ textView: IntrinsicTextView, context: Context) {
        context.coordinator.colorScheme = colorScheme
        context.coordinator.maxWidth = maxWidth
        textView.frame.size.width = maxWidth
        textView.textContainer?.containerSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)

        let attrString = context.coordinator.buildAttributedString(inlines)
        textView.textStorage?.setAttributedString(attrString)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private enum Trait {
            case emphasis
            case strong
        }

        let style: NativeMarkdownStyle
        var colorScheme: ColorScheme
        var maxWidth: CGFloat
        weak var textView: NSTextView?

        init(style: NativeMarkdownStyle, colorScheme: ColorScheme, maxWidth: CGFloat) {
            self.style = style
            self.colorScheme = colorScheme
            self.maxWidth = maxWidth
        }

        func buildAttributedString(_ inlines: [NativeMarkdownInline]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            var traits: Set<Trait> = []

            func appendInlines(_ items: [NativeMarkdownInline]) {
                for inline in items {
                    switch inline.kind {
                    case let .text(text):
                        appendText(text, to: result, traits: traits)
                    case .softBreak, .lineBreak:
                        result.append(NSAttributedString(string: "\n", attributes: textAttributes(traits: [])))
                    case let .emphasis(children):
                        traits.insert(.emphasis)
                        appendInlines(children)
                        traits.remove(.emphasis)
                    case let .strong(children):
                        traits.insert(.strong)
                        appendInlines(children)
                        traits.remove(.strong)
                    case let .code(code):
                        appendInlineCode(code, to: result)
                    case let .link(children, _):
                        appendInlines(children)
                    case let .math(formula):
                        appendInlineMath(formula, to: result)
                    }
                }
            }

            appendInlines(inlines)
            return result
        }

        private func textAttributes(traits: Set<Trait>) -> [NSAttributedString.Key: Any] {
            let weight: NSFont.Weight = traits.contains(.strong) ? .semibold : fontWeight(for: style.proseWeight)
            let font = NSFont.systemFont(ofSize: style.proseFontSize, weight: weight)
            let textColor = colorScheme == .light ? NSColor.black.withAlphaComponent(0.87) : NSColor.white.withAlphaComponent(0.92)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]
            if traits.contains(.emphasis) {
                attrs[.obliqueness] = 0.1
            }
            return attrs
        }

        private func fontWeight(for weight: Font.Weight) -> NSFont.Weight {
            switch weight {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            default: return .regular
            }
        }

        private func appendText(_ text: String, to result: NSMutableAttributedString, traits: Set<Trait>) {
            result.append(NSAttributedString(string: text, attributes: textAttributes(traits: traits)))
        }

        private func appendInlineCode(_ code: String, to result: NSMutableAttributedString) {
            let font = NSFont.monospacedSystemFont(ofSize: style.codeFontSize, weight: .regular)
            let textColor = NSColor(style.codeTextColor)
            let bgColor = NSColor(style.codeFillColor)
            let range = NSRange(location: result.length, length: 0)
            result.append(NSAttributedString(string: code, attributes: [
                .font: font,
                .foregroundColor: textColor,
                .backgroundColor: bgColor
            ]))
            result.addAttribute(.font, value: font, range: range)
            result.addAttribute(.foregroundColor, value: textColor, range: range)
            result.addAttribute(.backgroundColor, value: bgColor, range: range)
        }

        private func appendInlineMath(_ formula: String, to result: NSMutableAttributedString) {
            guard let image = NativeMathImageRenderer.image(
                formula: formula,
                fontSize: style.proseFontSize,
                textColor: NSColor(style.mathTextColor),
                mode: .inline
            ) else {
                result.append(NSAttributedString(string: " \(formula) ", attributes: [
                    .font: NSFont.systemFont(ofSize: style.proseFontSize, weight: .regular),
                    .foregroundColor: NSColor(style.mathTextColor)
                ]))
                return
            }

            let attachment = NSTextAttachment()
            attachment.image = image

            let lineHeight = style.proseFontSize * 1.4
            let imageHeight = image.size.height
            attachment.bounds = CGRect(
                x: 0,
                y: (lineHeight - imageHeight) / 2 - style.proseFontSize * 0.1,
                width: image.size.width,
                height: imageHeight
            )

            let attachStr = NSAttributedString(attachment: attachment)
            result.append(attachStr)
        }
    }
}

final class IntrinsicTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(ceil(used.height), 20))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" || event.charactersIgnoringModifiers == "a" {
                return super.performKeyEquivalent(with: event)
            }
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}