import SwiftUI
import WebKit

struct WebMarkdownView: View {
    let text: String
    var isUser = false
    var widthMode: NotchMarkdownWidthMode = .fillParent
    var style: NativeMarkdownStyle
    var colorScheme: ColorScheme

    @State private var height: CGFloat = 24

    var body: some View {
        WebMarkdownRenderer(
            text: text,
            isUser: isUser,
            widthMode: widthMode,
            style: style,
            colorScheme: colorScheme,
            height: $height
        )
        .frame(height: height)
    }
}

private struct WebMarkdownRenderer: NSViewRepresentable {
    let text: String
    var isUser = false
    var widthMode: NotchMarkdownWidthMode = .fillParent
    var style: NativeMarkdownStyle
    var colorScheme: ColorScheme
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "height")

        context.coordinator.themeKey = colorScheme == .light ? "light" : "dark"
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html(colorScheme: colorScheme, style: style), baseURL: Self.webMarkdownResourceURL())
        context.coordinator.pending = Payload(text: text, isUser: isUser, widthMode: widthMode, style: style, colorScheme: colorScheme)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let themeKey = colorScheme == .light ? "light" : "dark"
        if context.coordinator.themeKey != themeKey {
            context.coordinator.themeKey = themeKey
            context.coordinator.didFinishLoad = false
            context.coordinator.resetRenderCache()
            webView.loadHTMLString(Self.html(colorScheme: colorScheme, style: style), baseURL: Self.webMarkdownResourceURL())
        }

        let payload = Payload(text: text, isUser: isUser, widthMode: widthMode, style: style, colorScheme: colorScheme)
        context.coordinator.pending = payload
        guard context.coordinator.didFinishLoad else { return }
        context.coordinator.apply(payload, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.pending = nil
        coordinator.didFinishLoad = false
        coordinator.resetRenderCache()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var didFinishLoad = false
        var pending: Payload?
        var themeKey = ""
        private var lastKey = ""
        private var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func resetRenderCache() {
            lastKey = ""
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let pending {
                apply(pending, to: webView)
            }
        }

        func apply(_ payload: Payload, to webView: WKWebView) {
            let key = payload.cacheKey
            guard key != lastKey else { return }
            lastKey = key

            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.renderMarkdown(\(json));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "height", let heightValue = message.body as? Int {
                DispatchQueue.main.async { self.height.wrappedValue = CGFloat(heightValue) }
            }
        }
    }

    struct Payload: Encodable {
        let text: String
        let isUser: Bool
        let widthMode: NotchMarkdownWidthMode
        let style: NativeMarkdownStyle
        let colorScheme: ColorScheme

        var cacheKey: String {
            "\(isUser)|\(widthMode.cssMaxWidth ?? "")|\(colorScheme == .light)|\(style.proseFontSize)|\(style.codeFontSize)|\(text)"
        }

        enum CodingKeys: String, CodingKey {
            case text, isUser, maxWidth, isLight, proseFontSize, codeFontSize
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(isUser, forKey: .isUser)
            try container.encode(widthMode.cssMaxWidth, forKey: .maxWidth)
            try container.encode(colorScheme == .light, forKey: .isLight)
            try container.encode(style.proseFontSize, forKey: .proseFontSize)
            try container.encode(style.codeFontSize, forKey: .codeFontSize)
        }
    }

    private static func html(colorScheme: ColorScheme, style: NativeMarkdownStyle) -> String {
        let script = renderScript()
        let highlightTheme = colorScheme == .light ? "highlight/xcode.min.css" : "highlight/atom-one-dark.min.css"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: \(colorScheme == .light ? "#ffffff" : "transparent");
              color: \(colorScheme == .light ? "rgba(0,0,0,.87)" : "rgba(255,255,255,.92)");
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", "SF Pro Text", sans-serif;
              font-size: \(style.proseFontSize)px;
              font-weight: 500;
              overflow: hidden;
              -webkit-user-select: text;
            }
            #root {
              box-sizing: border-box;
              width: 100%;
              background: \(colorScheme == .light ? "#ffffff" : "transparent");
            }
            .markdown {
              box-sizing: border-box;
              width: 100%;
              line-height: 1.5;
              overflow-wrap: anywhere;
            }
            .markdown.user {
              text-align: right;
              margin-left: auto;
            }
            .markdown.hug {
              width: fit-content;
              max-width: var(--max-width);
            }
            p, ul, ol, blockquote, pre, table, .katex-display { margin: 0 0 6px 0; }
            p:last-child, ul:last-child, ol:last-child, blockquote:last-child, pre:last-child, table:last-child, .katex-display:last-child { margin-bottom: 0; }
            h1, h2, h3, h4, h5, h6 {
              margin: 12px 0 4px;
              line-height: 1.25;
              overflow-wrap: anywhere;
              color: \(colorScheme == .light ? "rgba(0,0,0,.95)" : "rgba(255,255,255,.95)");
            }
            h1:first-child, h2:first-child, h3:first-child, h4:first-child, h5:first-child, h6:first-child { margin-top: 0; }
            h1 { font-size: 1.35em; font-weight: 700; }
            h2 { font-size: 1.2em; font-weight: 650; }
            h3, h4, h5, h6 { font-size: 1.08em; font-weight: 600; }
            strong { font-weight: 650; }
            code {
              font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
              font-size: \(style.codeFontSize)px;
              background: \(colorScheme == .light ? "rgba(0,0,0,.08)" : "rgba(255,255,255,.08)");
              border-radius: 4px;
              padding: 1px 4px;
              font-weight: 450;
            }
            pre {
              box-sizing: border-box;
              padding: 0;
              border-radius: 8px;
              background: \(colorScheme == .light ? "rgba(0,0,0,.04)" : "rgba(255,255,255,.06)");
              border: .5px solid \(colorScheme == .light ? "rgba(0,0,0,.1)" : "rgba(255,255,255,.06)");
              overflow-x: auto;
              text-align: left;
            }
            pre code {
              display: block;
              padding: 10px;
              background: transparent !important;
              border-radius: 8px;
              white-space: pre;
            }
            blockquote {
              border-left: 3px solid \(colorScheme == .light ? "rgba(0,0,0,.25)" : "rgba(255,255,255,.08)");
              padding-left: 10px;
              color: \(colorScheme == .light ? "rgba(0,0,0,.7)" : "rgba(255,255,255,.7)");
            }
            table {
              width: 100%;
              border-collapse: collapse;
              border-radius: 6px;
              overflow: hidden;
              border: 1px solid \(colorScheme == .light ? "rgba(0,0,0,.1)" : "rgba(255,255,255,.06)");
              text-align: left;
            }
            th, td {
              padding: 5px 8px;
              border-bottom: .5px solid \(colorScheme == .light ? "rgba(0,0,0,.07)" : "rgba(255,255,255,.05)");
              color: \(colorScheme == .light ? "rgba(0,0,0,.87)" : "rgba(255,255,255,.92)");
            }
            th { background: \(colorScheme == .light ? "rgba(0,0,0,.06)" : "rgba(255,255,255,.12)"); }
            tr:nth-child(even) td { background: \(colorScheme == .light ? "rgba(0,0,0,.02)" : "rgba(255,255,255,.04)"); }
            .katex { font-size: 1em; }
            .katex-display {
              margin: 4px 0;
              border-radius: 8px;
              overflow-x: auto;
            }
          </style>
          <link rel="stylesheet" href="katex/katex.min.css">
          <link rel="stylesheet" href="\(highlightTheme)">
          <script src="katex/katex.min.js"></script>
          <script src="highlight/highlight.min.js"></script>
        </head>
        <body>
          <div id="root"></div>
          <script>\(script)</script>
        </body>
        </html>
        """
    }

    private static func renderScript() -> String {
        guard let resourceURL = webMarkdownResourceURL() else { return "" }
        return (try? String(contentsOf: resourceURL.appendingPathComponent("render.js"), encoding: .utf8)) ?? ""
    }

    private static func webMarkdownResourceURL() -> URL? {
        if let url = NotchResourceBundle.url(forResource: "WebMarkdown", withExtension: nil) {
            return url
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Notch_Notch.bundle/WebMarkdown") {
            return url
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("WebMarkdown") {
            return url
        }
        return nil
    }
}

private extension NotchMarkdownWidthMode {
    var cssMaxWidth: String? {
        switch self {
        case .fillParent:
            return nil
        case let .hugContent(maxWidth):
            return "\(maxWidth)px"
        }
    }
}
