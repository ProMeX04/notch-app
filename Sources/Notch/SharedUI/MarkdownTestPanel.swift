import AppKit
import SwiftUI

@MainActor
public final class MarkdownTestPanelController {
    public static let shared = MarkdownTestPanelController()

    private var window: NSWindow?

    public init() {}

    public func show() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let view = MarkdownTestView()
        let controller = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 480, height: 400)
        window.center()
        window.title = "Markdown Test Panel (Debug)"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct MarkdownTestView: View {
    @State private var input: String = """
    # Test Markdown Rendering

    Here's some **bold** and *italic* text with `inline code`.

    ## Code Blocks

    ```swift
    func hello() {
        print("Hello from Notch!")
    }
    ```

    ```python
    def fibonacci(n):
        if n <= 1:
            return n
        return fibonacci(n-1) + fibonacci(n-2)
    ```

    ```bash
    echo "Hello world"
    ls -la
    ```

    ```json
    {
      "name": "Notch",
      "version": "1.0.8",
      "features": ["markdown", "math", "syntax-highlight"]
    }
    ```

    ## Math Blocks

    Inline math: $E = mc^2$ and $\\int_0^1 x^2 dx = \\frac{1}{3}$

    Block math:

    $$\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}$$

    $$\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$

    ## Mixed Content

    | Feature | Status |
    |---------|--------|
    | Syntax Highlight | ✅ |
    | Math Rendering | ✅ |
    | Inline Math | ✅ |

    > Blockquotes work too!
    """

    @State private var isUser = false
    @State private var colorScheme: ColorScheme = .dark
    @State private var useHugWidth = false
    @State private var showProse = true

    var body: some View {
        HSplitView {
            // Editor pane
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Input (Markdown)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        input = defaultInput
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                }

                TextEditor(text: $input)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }
            .frame(minWidth: 280)

            // Preview pane
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Picker("", selection: $colorScheme) {
                        Text("Dark").tag(ColorScheme.dark)
                        Text("Light").tag(ColorScheme.light)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)

                    Toggle("Hug", isOn: $useHugWidth)
                        .toggleStyle(.switch)
                        .font(.system(size: 11))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if showProse {
                            NotchMarkdownView(
                                text: input,
                                isUser: isUser,
                                widthMode: useHugWidth ? .hugContent(maxWidth: 400) : .fillParent
                            )
                            .environment(\.colorScheme, colorScheme)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: colorScheme == .dark ? .textBackgroundColor : .windowBackgroundColor))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minWidth: 300)
        }
        .padding(12)
    }

    private var defaultInput: String { """
# Test Markdown Rendering

Here's some **bold** and *italic* text with `inline code`.

## Code Blocks

```swift
func hello() {
    print("Hello from Notch!")
}
```

## Math Blocks

Inline math: $E = mc^2$ and $\\int_0^1 x^2 dx = \\frac{1}{3}$

Block math:

$$\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}$$
""" }
}