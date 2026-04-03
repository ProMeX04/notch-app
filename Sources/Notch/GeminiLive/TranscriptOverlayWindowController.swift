import AppKit
import Combine
import SwiftUI

// MARK: - SwiftUI View

private struct TranscriptOverlayView: View {
    let userText: String
    let modelText: String
    let isModelSpeaking: Bool
    let toolAction: ToolActionToast?
    let imageRequest: ImageOverlayRequest?

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if let imageRequest {
                CompactImageAboveBubbles(request: imageRequest)
            }
            if !userText.isEmpty {
                BubbleRow(text: userText, isUser: true)
            }
            if !modelText.isEmpty {
                BubbleRow(text: modelText, isUser: false, isAnimating: isModelSpeaking)
            }
            if let toolAction {
                ToolBubbleRow(action: toolAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Small preview above chat bubbles: image only, no border, no caption, no chrome.
private struct CompactImageAboveBubbles: View {
    let request: ImageOverlayRequest
    private let width: CGFloat = 306
    private let height: CGFloat = 174

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            AsyncImage(url: request.imageURL, transaction: Transaction(animation: nil)) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    Color.clear
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 0)
        }
    }
}

private struct ToolBubbleRow: View {
    let action: ToolActionToast

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text(action.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .systemTeal).opacity(0.18),
                                        Color.black.opacity(0.12),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct BubbleRow: View {
    let text: String
    let isUser: Bool
    var isAnimating: Bool = false

    @State private var dotPhase = false

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var bubbleTint: LinearGradient {
        if isUser {
            return LinearGradient(
                colors: [
                    Color(nsColor: .systemBlue).opacity(0.22),
                    Color.black.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.black.opacity(0.24),
                Color.white.opacity(0.05),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleBorder: Color {
        Color.white.opacity(isUser ? 0.16 : 0.12)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Both branches fill full width so bubbles are symmetric around the center.
            // User messages sit on the left; model messages sit on the right.
            if !isUser { Spacer(minLength: 0) }

            HStack(alignment: .bottom, spacing: 6) {
                NotchMarkdownView(text: text, isUser: isUser)

                if isAnimating && !isUser {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(.white.opacity(0.7))
                                .frame(width: 4, height: 4)
                                .scaleEffect(dotPhase ? 1.0 : 0.4)
                                .animation(
                                    .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                    value: dotPhase
                                )
                        }
                    }
                    .onAppear { dotPhase = true }
                    .onDisappear { dotPhase = false }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                bubbleShape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        bubbleShape.fill(bubbleTint)
                    }
                    .overlay {
                        bubbleShape.stroke(bubbleBorder, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            }

            if isUser { Spacer(minLength: 0) }
        }
    }
}

// MARK: - Window Controller

@MainActor
final class TranscriptOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TranscriptOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    /// Captured when auto-hide fires. Suppresses re-opening the panel when
    /// only extras (image/toast) clear while transcript text hasn't changed.
    private var suppressedTranscriptKey: String? = nil

    private let panelWidth: CGFloat = 520
    private let maxPanelHeight: CGFloat = 1200
    private let notchSpacing: CGFloat = 4

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen

        guard let panel else { return }
        let targetFrame = panelFrame(on: screen())
        panel.setFrame(targetFrame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: targetFrame.size)
    }

    func observe(gemini: GeminiLiveViewModel) {
        self.gemini = gemini
        suppressedTranscriptKey = nil
        cancellables.removeAll()

        gemini.$overlayInput
            .receive(on: DispatchQueue.main)
            .sink { [weak self] input in
                guard let self else { return }
                if !input.shouldShow {
                    self.hide(animated: true)
                } else {
                    self.apply(input)
                }
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        gemini = nil
        cancellables.removeAll()
        hide(animated: true)
    }

    // MARK: - Private

    private func apply(_ input: TranscriptOverlayInput) {
        // Suppress re-opening when only extras (image/toast) cleared and transcript unchanged.
        if panel == nil,
           let suppressed = suppressedTranscriptKey,
           input.transcriptKey == suppressed,
           input.toolAction == nil, input.imageRequest == nil {
            return
        }
        suppressedTranscriptKey = nil
        showOrUpdate(with: input)
        scheduleAutoHide(isModelSpeaking: input.isModelSpeaking)
    }

    private func screen() -> NSScreen {
        preferredScreen
        ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        ?? NSScreen.main
        ?? NSScreen.screens[0]
    }

    private func panelFrame(on screen: NSScreen) -> CGRect {
        let closedNotchHeight = NotchMetrics.baseClosedSize(for: screen).height
        let x = screen.frame.midX - panelWidth / 2
        let y = screen.frame.maxY - closedNotchHeight - notchSpacing - maxPanelHeight
        return CGRect(x: x, y: y, width: panelWidth, height: maxPanelHeight)
    }

    private func showOrUpdate(with input: TranscriptOverlayInput) {
        let newView = TranscriptOverlayView(
            userText: input.subsEnabled ? input.userText : "",
            modelText: input.subsEnabled ? input.modelText : "",
            isModelSpeaking: input.isModelSpeaking && input.subsEnabled,
            toolAction: input.toolAction,
            imageRequest: input.imageRequest
        )

        // If panel already exists, just update content
        if let panel, let hv = hostingView {
            hv.rootView = newView
            let targetFrame = panelFrame(on: screen())
            panel.setFrame(targetFrame, display: true)
            hv.frame = CGRect(origin: .zero, size: targetFrame.size)
            ensurePanelVisible()
            return
        }

        // Create a large stable window once
        let sc = screen()
        let frame = panelFrame(on: sc)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let hv = NSHostingView(rootView: newView)
        hv.frame = CGRect(origin: .zero, size: frame.size)
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanelVisible() {
        guard let panel, panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        hideTask?.cancel()
        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    panel.orderOut(nil)
                    self?.panel = nil
                    self?.hostingView = nil
                    self?.gemini?.clearDisplayedImageOverlay()
                }
            })
        } else {
            panel.orderOut(nil)
            self.panel = nil
            self.hostingView = nil
            gemini?.clearDisplayedImageOverlay()
        }
    }

    private func scheduleAutoHide(isModelSpeaking: Bool) {
        hideTask?.cancel()
        guard !isModelSpeaking else { return }

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.suppressedTranscriptKey = self.gemini?.overlayInput.transcriptKey
            self.hide(animated: true)
        }
    }
}
