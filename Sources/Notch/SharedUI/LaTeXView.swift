import AppKit
import iosMath
import SwiftUI

enum MathDisplayMode {
    case inline
    case block
}

struct LaTeXView: NSViewRepresentable {
    let latex: String
    var fontSize: CGFloat = 15
    var mode: MathDisplayMode = .inline
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.mode = mode == .inline ? .text : .display
        label.textAlignment = mode == .block ? .center : .left
        label.backgroundColor = .clear
        label.textColor = textColor
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.fontSize = fontSize
        label.mode = mode == .inline ? .text : .display
        label.textAlignment = mode == .block ? .center : .left
        label.textColor = textColor
    }
}

@MainActor
enum NativeMathImageRenderer {
    static func image(formula: String, fontSize: CGFloat, textColor: NSColor, mode: MathDisplayMode) -> NSImage? {
        let key = "\(formula)|\(fontSize)|\(textColor)|\(mode == .inline)"
        if let cached = cache[key] { return cached }

        let label = MTMathUILabel()
        label.latex = formula
        label.fontSize = fontSize
        label.mode = mode == .inline ? .text : .display
        label.textColor = textColor
        label.backgroundColor = .clear

        label.needsLayout = true
        label.layoutSubtreeIfNeeded()
        let size = label.intrinsicContentSize
        let finalSize = CGSize(width: max(24, size.width), height: max(fontSize * 1.4, size.height))
        label.frame = NSRect(origin: .zero, size: finalSize)

        let pdfData = label.dataWithPDF(inside: label.bounds)
        let image = NSImage(data: pdfData) ?? NSImage(size: finalSize)
        image.size = finalSize
        cache[key] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]
}
