import Foundation
import Markdown

struct NativeMarkdownDocument {
    let blocks: [NativeMarkdownBlock]
}

struct NativeMarkdownBlock: Identifiable {
    enum Kind {
        case paragraph([NativeMarkdownInline])
        case heading(level: Int, inlines: [NativeMarkdownInline])
        case blockquote([NativeMarkdownBlock])
        case unorderedList([[NativeMarkdownBlock]])
        case orderedList(start: Int, items: [[NativeMarkdownBlock]])
        case codeBlock(language: String?, code: String)
        case table(headers: [[NativeMarkdownInline]], rows: [[[NativeMarkdownInline]]])
        case mathBlock(String)
        case thematicBreak
    }

    let id: Int
    let kind: Kind
}

struct NativeMarkdownInline: Identifiable {
    enum Kind {
        case text(String)
        case softBreak
        case lineBreak
        case emphasis([NativeMarkdownInline])
        case strong([NativeMarkdownInline])
        case code(String)
        case link(text: [NativeMarkdownInline], destination: String?)
        case math(String)
    }

    let id: Int
    let kind: Kind
}

enum NativeMarkdownParser {
    static func parse(_ markdown: String) -> NativeMarkdownDocument {
        let math = NativeMarkdownMathPreprocessor.process(markdown)
        let document = Document(parsing: math.markdown)
        var converter = NativeMarkdownASTConverter(math: math)
        return NativeMarkdownDocument(blocks: converter.blocks(from: document.children))
    }
}

private struct NativeMarkdownMathPreprocessor {
    let markdown: String
    let inline: [String: String]
    let blocks: [String: String]

    static func process(_ source: String) -> NativeMarkdownMathPreprocessor {
        var output = ""
        var inline: [String: String] = [:]
        var blocks: [String: String] = [:]
        var index = source.startIndex
        var inlineCount = 0
        var blockCount = 0

        while index < source.endIndex {
            if source[index] == "`" {
                let tickCount = countRun(of: "`", in: source, from: index)
                let close = findBacktickClose(in: source, from: source.index(index, offsetBy: tickCount), tickCount: tickCount)
                let end = close.map { source.index($0, offsetBy: tickCount) } ?? source.endIndex
                output.append(contentsOf: source[index..<end])
                index = end
                continue
            }

            if source[index] == "\\", source.index(after: index) < source.endIndex, source[source.index(after: index)] == "$" {
                output.append("\\$")
                index = source.index(index, offsetBy: 2)
                continue
            }

            if source[index...].hasPrefix("$$"), !isEscaped(source, index) {
                let formulaStart = source.index(index, offsetBy: 2)
                guard let close = findUnescapedDelimiter("$$", in: source, from: formulaStart) else {
                    output.append(contentsOf: source[index...])
                    break
                }
                let formula = String(source[formulaStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                if formula.isEmpty {
                    output.append("$$$$")
                } else {
                    let token = "NATIVE_MATH_BLOCK_\(blockCount)"
                    blockCount += 1
                    blocks[token] = formula
                    output.append("\n\n")
                    output.append(token)
                    output.append("\n\n")
                }
                index = source.index(close, offsetBy: 2)
                continue
            }

            if source[index] == "$", !isEscaped(source, index) {
                let formulaStart = source.index(after: index)
                if let close = findUnescapedDelimiter("$", in: source, from: formulaStart) {
                    let formula = String(source[formulaStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !formula.isEmpty, !formula.contains("\n") {
                        let token = "NATIVE_MATH_INLINE_\(inlineCount)"
                        inlineCount += 1
                        inline[token] = formula
                        output.append(token)
                        index = source.index(after: close)
                        continue
                    }
                }
            }

            output.append(source[index])
            index = source.index(after: index)
        }

        return NativeMarkdownMathPreprocessor(markdown: output, inline: inline, blocks: blocks)
    }

    private static func countRun(of character: Character, in source: String, from start: String.Index) -> Int {
        var count = 0
        var index = start
        while index < source.endIndex, source[index] == character {
            count += 1
            index = source.index(after: index)
        }
        return count
    }

    private static func findBacktickClose(in source: String, from start: String.Index, tickCount: Int) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index] == "`", countRun(of: "`", in: source, from: index) == tickCount {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func findUnescapedDelimiter(_ delimiter: String, in source: String, from start: String.Index) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index...].hasPrefix(delimiter), !isEscaped(source, index) {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func isEscaped(_ source: String, _ index: String.Index) -> Bool {
        var backslashCount = 0
        var cursor = index
        while cursor > source.startIndex {
            cursor = source.index(before: cursor)
            guard source[cursor] == "\\" else { break }
            backslashCount += 1
        }
        return !backslashCount.isMultiple(of: 2)
    }
}

private struct NativeMarkdownASTConverter {
    let math: NativeMarkdownMathPreprocessor
    private var blockID: Int
    private var inlineID: Int

    init(math: NativeMarkdownMathPreprocessor, blockID: Int = 0, inlineID: Int = 0) {
        self.math = math
        self.blockID = blockID
        self.inlineID = inlineID
    }

    mutating func blocks(from markupChildren: MarkupChildren) -> [NativeMarkdownBlock] {
        markupChildren.compactMap { block(from: $0) }
    }

    private mutating func block(from markup: Markup) -> NativeMarkdownBlock? {
        if let paragraph = markup as? Paragraph {
            let text = plainText(from: paragraph)
            if let formula = math.blocks[text.trimmingCharacters(in: .whitespacesAndNewlines)] {
                return makeBlock(.mathBlock(formula))
            }
            return makeBlock(.paragraph(inlines(from: paragraph.children)))
        }

        if let heading = markup as? Heading {
            return makeBlock(.heading(level: heading.level, inlines: inlines(from: heading.children)))
        }

        if let code = markup as? CodeBlock {
            return makeBlock(.codeBlock(language: code.language, code: code.code))
        }

        if markup is ThematicBreak {
            return makeBlock(.thematicBreak)
        }

        if let blockquote = markup as? BlockQuote {
            return makeBlock(.blockquote(blocks(from: blockquote.children)))
        }

        if let list = markup as? UnorderedList {
            let items = list.children.compactMap { item -> [NativeMarkdownBlock]? in
                guard let item = item as? ListItem else { return nil }
                return blocks(from: item.children)
            }
            return makeBlock(.unorderedList(items))
        }

        if let list = markup as? OrderedList {
            let items = list.children.compactMap { item -> [NativeMarkdownBlock]? in
                guard let item = item as? ListItem else { return nil }
                return blocks(from: item.children)
            }
            return makeBlock(.orderedList(start: Int(list.startIndex), items: items))
        }

        if let table = markup as? Table {
            return makeBlock(tableKind(from: table))
        }

        let children = blocks(from: markup.children)
        if children.count == 1 { return children[0] }
        if !children.isEmpty { return makeBlock(.blockquote(children)) }
        return nil
    }

    private mutating func tableKind(from table: Table) -> NativeMarkdownBlock.Kind {
        var headers: [[NativeMarkdownInline]] = []
        var rows: [[[NativeMarkdownInline]]] = []

        for child in table.children {
            if let head = child as? Table.Head {
                headers = tableCells(from: head.children)
            } else if let body = child as? Table.Body {
                rows = body.children.compactMap { row in tableCells(from: row.children) }
            }
        }

        return .table(headers: headers, rows: rows)
    }

    private mutating func tableCells(from children: MarkupChildren) -> [[NativeMarkdownInline]] {
        children.compactMap { child in
            if let cell = child as? Table.Cell {
                return inlines(from: cell.children)
            }
            return inlines(from: child.children)
        }
    }

    private mutating func inlines(from markupChildren: MarkupChildren) -> [NativeMarkdownInline] {
        var result: [NativeMarkdownInline] = []
        for child in markupChildren {
            result.append(contentsOf: inline(from: child))
        }
        return mergeAdjacentText(result)
    }

    private mutating func inline(from markup: Markup) -> [NativeMarkdownInline] {
        if let text = markup as? Text {
            return textInlines(text.string)
        }
        if markup is SoftBreak {
            return [makeInline(.softBreak)]
        }
        if markup is LineBreak {
            return [makeInline(.lineBreak)]
        }
        if let code = markup as? InlineCode {
            if let formula = math.inline[code.code] {
                return [makeInline(.math(formula))]
            }
            return [makeInline(.code(code.code))]
        }
        if let emphasis = markup as? Emphasis {
            return [makeInline(.emphasis(inlines(from: emphasis.children)))]
        }
        if let strong = markup as? Strong {
            return [makeInline(.strong(inlines(from: strong.children)))]
        }
        if let link = markup as? Link {
            return [makeInline(.link(text: inlines(from: link.children), destination: link.destination))]
        }
        return inlines(from: markup.children)
    }

    private mutating func textInlines(_ string: String) -> [NativeMarkdownInline] {
        var remaining = string
        var result: [NativeMarkdownInline] = []
        while let match = remaining.range(of: "NATIVE_MATH_INLINE_\\d+", options: .regularExpression) {
            let prefix = String(remaining[..<match.lowerBound])
            if !prefix.isEmpty { result.append(makeInline(.text(prefix))) }
            let token = String(remaining[match])
            if let formula = math.inline[token] {
                result.append(makeInline(.math(formula)))
            } else {
                result.append(makeInline(.text(token)))
            }
            remaining = String(remaining[match.upperBound...])
        }
        if !remaining.isEmpty { result.append(makeInline(.text(remaining))) }
        return result
    }

    private mutating func mergeAdjacentText(_ inlines: [NativeMarkdownInline]) -> [NativeMarkdownInline] {
        var result: [NativeMarkdownInline] = []
        for inline in inlines {
            if case let .text(text) = inline.kind,
               let last = result.last,
               case let .text(previous) = last.kind {
                result.removeLast()
                result.append(NativeMarkdownInline(id: last.id, kind: .text(previous + text)))
            } else {
                result.append(inline)
            }
        }
        return result
    }

    private mutating func plainText(from markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            if let text = child as? Text {
                result += text.string
            } else {
                result += plainText(from: child)
            }
        }
        return result
    }

    private mutating func makeBlock(_ kind: NativeMarkdownBlock.Kind) -> NativeMarkdownBlock {
        defer { blockID += 1 }
        return NativeMarkdownBlock(id: blockID, kind: kind)
    }

    private mutating func makeInline(_ kind: NativeMarkdownInline.Kind) -> NativeMarkdownInline {
        defer { inlineID += 1 }
        return NativeMarkdownInline(id: inlineID, kind: kind)
    }
}
