import AppKit
import Highlightr
import SwiftUI

struct NativeMarkdownStyle {
    let proseFontSize: CGFloat
    let codeFontSize: CGFloat
    let proseWeight: Font.Weight
    let proseDesign: Font.Design
    let codeTextColor: Color
    let codeFillColor: Color
    let codeStrokeColor: Color
    let mathTextColor: Color
    let mathFillColor: Color
    let mathStrokeColor: Color

    static func notch(colorScheme: ColorScheme) -> NativeMarkdownStyle {
        let isLight = colorScheme == .light
        return NativeMarkdownStyle(
            proseFontSize: 13,
            codeFontSize: 12,
            proseWeight: .medium,
            proseDesign: .rounded,
            codeTextColor: isLight ? .black.opacity(0.92) : .white.opacity(0.95),
            codeFillColor: isLight ? .black.opacity(0.06) : .white.opacity(0.06),
            codeStrokeColor: isLight ? .black.opacity(0.12) : .white.opacity(0.1),
            mathTextColor: isLight ? .black.opacity(0.9) : .white.opacity(0.92),
            mathFillColor: isLight ? .black.opacity(0.045) : .clear,
            mathStrokeColor: isLight ? .black.opacity(0.1) : .clear
        )
    }

    static func agentResults(colorScheme: ColorScheme, fontSize: CGFloat, codeFontSize: CGFloat) -> NativeMarkdownStyle {
        let isLight = colorScheme == .light
        return NativeMarkdownStyle(
            proseFontSize: fontSize,
            codeFontSize: codeFontSize,
            proseWeight: .regular,
            proseDesign: .default,
            codeTextColor: isLight ? .black.opacity(0.92) : .white.opacity(0.95),
            codeFillColor: isLight ? .black.opacity(0.06) : .white.opacity(0.06),
            codeStrokeColor: isLight ? .black.opacity(0.12) : .white.opacity(0.1),
            mathTextColor: isLight ? .black.opacity(0.9) : .white.opacity(0.92),
            mathFillColor: isLight ? .black.opacity(0.045) : .clear,
            mathStrokeColor: isLight ? .black.opacity(0.1) : .clear
        )
    }
}

struct NativeMarkdownRenderer: View {
    let text: String
    var isUser = false
    var widthMode: NotchMarkdownWidthMode = .fillParent
    var style: NativeMarkdownStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let document = NativeMarkdownParser.parse(text)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(document.blocks) { block in
                NativeMarkdownBlockView(block: block, isUser: isUser, widthMode: widthMode, style: style)
            }
        }
        .frame(maxWidth: maxWidth, alignment: isUser ? .trailing : .leading)
    }

    private var maxWidth: CGFloat? {
        switch widthMode {
        case .fillParent: .infinity
        case let .hugContent(maxWidth): maxWidth
        }
    }
}

private struct NativeMarkdownBlockView: View {
    let block: NativeMarkdownBlock
    let isUser: Bool
    let widthMode: NotchMarkdownWidthMode
    let style: NativeMarkdownStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch block.kind {
        case let .paragraph(inlines):
            NativeMarkdownInlineView(inlines: inlines, style: style, maxWidth: concreteMaxWidth)
                .frame(maxWidth: maxWidth, alignment: isUser ? .trailing : .leading)
        case let .heading(level, inlines):
            NativeMarkdownInlineView(inlines: inlines, style: headingStyle(level: level), maxWidth: concreteMaxWidth)
                .frame(maxWidth: maxWidth, alignment: isUser ? .trailing : .leading)
        case let .blockquote(blocks):
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(colorScheme == .light ? Color.black.opacity(0.2) : Color.white.opacity(0.2))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(blocks) { nested in
                        NativeMarkdownBlockView(block: nested, isUser: false, widthMode: widthMode, style: quoteStyle)
                    }
                }
            }
            .frame(maxWidth: maxWidth, alignment: isUser ? .trailing : .leading)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NativeMarkdownListRow(marker: "•", blocks: item, widthMode: widthMode, style: style)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
        case let .orderedList(start, items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    NativeMarkdownListRow(marker: "\(start + offset).", blocks: item, widthMode: widthMode, style: style)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
        case let .codeBlock(language, code):
            NativeMarkdownCodeBlockView(code: code, language: language, style: style, widthMode: widthMode, colorScheme: colorScheme)
        case let .table(headers, rows):
            NativeMarkdownTableView(headers: headers, rows: rows, style: style, widthMode: widthMode)
        case let .mathBlock(formula):
            NativeMarkdownMathBlockView(formula: formula, style: style, widthMode: widthMode)
        case .thematicBreak:
            Rectangle()
                .fill(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.12))
                .frame(height: 1)
                .frame(maxWidth: maxWidth)
        }
    }

    private var maxWidth: CGFloat? {
        switch widthMode {
        case .fillParent: .infinity
        case let .hugContent(maxWidth): maxWidth
        }
    }

    private var concreteMaxWidth: CGFloat {
        switch widthMode {
        case .fillParent: 520
        case let .hugContent(maxWidth): maxWidth
        }
    }

    private func headingStyle(level: Int) -> NativeMarkdownStyle {
        let scale: CGFloat = switch level {
        case 1: 1.35
        case 2: 1.2
        default: 1.08
        }
        return NativeMarkdownStyle(
            proseFontSize: style.proseFontSize * scale,
            codeFontSize: style.codeFontSize,
            proseWeight: level == 1 ? .bold : .semibold,
            proseDesign: style.proseDesign,
            codeTextColor: style.codeTextColor,
            codeFillColor: style.codeFillColor,
            codeStrokeColor: style.codeStrokeColor,
            mathTextColor: style.mathTextColor,
            mathFillColor: style.mathFillColor,
            mathStrokeColor: style.mathStrokeColor
        )
    }

    private var quoteStyle: NativeMarkdownStyle {
        NativeMarkdownStyle(
            proseFontSize: style.proseFontSize,
            codeFontSize: style.codeFontSize,
            proseWeight: style.proseWeight,
            proseDesign: style.proseDesign,
            codeTextColor: style.codeTextColor,
            codeFillColor: style.codeFillColor,
            codeStrokeColor: style.codeStrokeColor,
            mathTextColor: style.mathTextColor,
            mathFillColor: style.mathFillColor,
            mathStrokeColor: style.mathStrokeColor
        )
    }
}

private struct NativeMarkdownListRow: View {
    let marker: String
    let blocks: [NativeMarkdownBlock]
    let widthMode: NotchMarkdownWidthMode
    let style: NativeMarkdownStyle

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(marker)
                .font(.system(size: style.proseFontSize, weight: style.proseWeight, design: style.proseDesign))
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(blocks) { block in
                    NativeMarkdownBlockView(block: block, isUser: false, widthMode: widthMode, style: style)
                }
            }
        }
    }
}

private struct NativeMarkdownInlineView: View {
    let inlines: [NativeMarkdownInline]
    let style: NativeMarkdownStyle
    var maxWidth: CGFloat = 520

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if containsMath(inlines) {
            NativeMarkdownInlineTextView(inlines: inlines, style: style, maxWidth: maxWidth)
                .lineSpacing(2)
                .textSelection(.enabled)
        } else {
            Text(attributedString(inlines))
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }

    private func containsMath(_ inlines: [NativeMarkdownInline]) -> Bool {
        for inline in inlines {
            if case .math = inline.kind { return true }
            if case let .emphasis(children) = inline.kind, containsMath(children) { return true }
            if case let .strong(children) = inline.kind, containsMath(children) { return true }
            if case let .link(children, _) = inline.kind, containsMath(children) { return true }
        }
        return false
    }

    private func attributedString(_ inlines: [NativeMarkdownInline]) -> AttributedString {
        var result = AttributedString()
        append(inlines, to: &result, traits: [])
        return result
    }

    private enum Trait {
        case emphasis
        case strong
    }

    private func append(_ inlines: [NativeMarkdownInline], to result: inout AttributedString, traits: Set<Trait>) {
        for inline in inlines {
            switch inline.kind {
            case let .text(text):
                appendText(text, to: &result, traits: traits)
            case .softBreak:
                appendText("\n", to: &result, traits: traits)
            case .lineBreak:
                appendText("\n", to: &result, traits: traits)
            case let .emphasis(children):
                append(children, to: &result, traits: traits.union([.emphasis]))
            case let .strong(children):
                append(children, to: &result, traits: traits.union([.strong]))
            case let .code(code):
                var fragment = AttributedString(code)
                fragment.font = .system(size: style.codeFontSize, design: .monospaced)
                fragment.foregroundColor = style.codeTextColor
                fragment.backgroundColor = style.codeFillColor
                result += fragment
            case let .link(children, _):
                append(children, to: &result, traits: traits)
            case let .math(formula):
                var fragment = AttributedString(" \(formula) ")
                fragment.font = .system(size: style.proseFontSize, design: .serif)
                fragment.foregroundColor = style.mathTextColor
                result += fragment
            }
        }
    }

    private func appendText(_ text: String, to result: inout AttributedString, traits: Set<Trait>) {
        var fragment = AttributedString(text)
        let weight: Font.Weight = traits.contains(.strong) ? .semibold : style.proseWeight
        fragment.font = .system(size: style.proseFontSize, weight: weight, design: style.proseDesign)
        fragment.foregroundColor = colorScheme == .light ? Color.black.opacity(0.87) : Color.white.opacity(0.92)
        if traits.contains(.emphasis) {
            fragment.inlinePresentationIntent = .emphasized
        }
        result += fragment
    }
}

private struct NativeMarkdownCodeBlockView: View {
    let code: String
    let language: String?
    let style: NativeMarkdownStyle
    let widthMode: NotchMarkdownWidthMode
    let colorScheme: ColorScheme

    var body: some View {
        Text(NativeMarkdownCodeHighlighter.highlight(code: code, language: language, fontSize: style.codeFontSize, textColor: style.codeTextColor, colorScheme: colorScheme))
            .lineSpacing(2)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(style.codeFillColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style.codeStrokeColor, lineWidth: 0.5)
            )
    }

    private var maxWidth: CGFloat? {
        switch widthMode {
        case .fillParent: .infinity
        case let .hugContent(maxWidth): maxWidth
        }
    }
}

@MainActor
private enum NativeMarkdownCodeHighlighter {
    static func highlight(code: String, language: String?, fontSize: CGFloat, textColor: Color, colorScheme: ColorScheme) -> AttributedString {
        let theme = colorScheme == .light ? "xcode" : "atom-one-dark"
        let key = "\(theme)|\(language ?? "")|\(fontSize)|\(code)"
        if let cached = cache[key] { return cached }

        let nsAttr: NSAttributedString
        if let highlighted = highlighter.highlight(code: code, language: language, fontSize: fontSize, colorScheme: colorScheme) {
            nsAttr = highlighted
        } else {
            nsAttr = NSAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                    .foregroundColor: NSColor(textColor),
                ]
            )
        }
        let attr = AttributedString(nsAttr)
        cache[key] = attr
        return attr
    }

    private static let highlighter = NativeMarkdownHighlighter()
    private static var cache: [String: AttributedString] = [:]
}

@MainActor
private final class NativeMarkdownHighlighter {
    private let highlightr = Highlightr()
    private var cache: [String: NSAttributedString] = [:]

    func highlight(code: String, language: String?, fontSize: CGFloat, colorScheme: ColorScheme) -> NSAttributedString? {
        let theme = colorScheme == .light ? "xcode" : "atom-one-dark"
        let key = "\(theme)|\(language ?? "")|\(fontSize)|\(code)"
        if let cached = cache[key] { return cached }

        highlightr?.setTheme(to: theme)
        let highlighted = language.flatMap { highlightr?.highlight(code, as: $0) } ?? highlightr?.highlight(code)
        guard let highlighted else { return nil }
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        mutable.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: NSRange(location: 0, length: mutable.length))
        cache[key] = mutable
        return mutable
    }
}

private struct NativeMarkdownMathBlockView: View {
    let formula: String
    let style: NativeMarkdownStyle
    let widthMode: NotchMarkdownWidthMode

    var body: some View {
        LaTeXView(latex: formula, fontSize: style.proseFontSize + 2, mode: .block, textColor: NSColor(style.mathTextColor))
            .frame(minHeight: 28)
            .padding(.vertical, 4)
            .frame(maxWidth: maxWidth, alignment: .center)
    }

    private var maxWidth: CGFloat? {
        switch widthMode {
        case .fillParent: .infinity
        case let .hugContent(maxWidth): maxWidth
        }
    }
}

private struct NativeMarkdownTableView: View {
    let headers: [[NativeMarkdownInline]]
    let rows: [[[NativeMarkdownInline]]]
    let style: NativeMarkdownStyle
    let widthMode: NotchMarkdownWidthMode

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if !headers.isEmpty {
                tableRow(headers, isHeader: true, rowIndex: 0)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                tableRow(row, isHeader: false, rowIndex: index)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colorScheme == .light ? Color.black.opacity(0.15) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(6)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func tableRow(_ cells: [[NativeMarkdownInline]], isHeader: Bool, rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(normalized(cells).enumerated()), id: \.offset) { _, cell in
                NativeMarkdownInlineView(inlines: cell, style: isHeader ? headerStyle : style, maxWidth: 220)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, isHeader ? 6 : 5)
                    .background(rowBackground(isHeader: isHeader, rowIndex: rowIndex))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func normalized(_ cells: [[NativeMarkdownInline]]) -> [[NativeMarkdownInline]] {
        let targetCount = max(headers.count, cells.count, 1)
        if cells.count >= targetCount { return Array(cells.prefix(targetCount)) }
        return cells + Array(repeating: [], count: targetCount - cells.count)
    }

    private func rowBackground(isHeader: Bool, rowIndex: Int) -> Color {
        if isHeader {
            return colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.15)
        }
        if rowIndex.isMultiple(of: 2) {
            return colorScheme == .light ? Color.black.opacity(0.02) : Color.white.opacity(0.03)
        }
        return colorScheme == .light ? .clear : Color.white.opacity(0.05)
    }

    private var headerStyle: NativeMarkdownStyle {
        NativeMarkdownStyle(
            proseFontSize: style.proseFontSize,
            codeFontSize: style.codeFontSize,
            proseWeight: .semibold,
            proseDesign: style.proseDesign,
            codeTextColor: style.codeTextColor,
            codeFillColor: style.codeFillColor,
            codeStrokeColor: style.codeStrokeColor,
            mathTextColor: style.mathTextColor,
            mathFillColor: style.mathFillColor,
            mathStrokeColor: style.mathStrokeColor
        )
    }

    private var maxWidth: CGFloat? {
        switch widthMode {
        case .fillParent: .infinity
        case let .hugContent(maxWidth): maxWidth
        }
    }
}
