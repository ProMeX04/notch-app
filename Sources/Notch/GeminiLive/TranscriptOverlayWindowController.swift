import AppKit
import Combine
import SwiftUI

// MARK: - SwiftUI View

private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .menu
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct TranscriptOverlayView: View {
    let modelText: String
    let isModelSpeaking: Bool
    let toolAction: ToolActionToast?
    let imageRequest: ImageOverlayRequest?

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if let imageRequest {
                CompactImageAboveCaption(request: imageRequest)
            }
            if !modelText.isEmpty || isModelSpeaking {
                HStack(alignment: .bottom, spacing: 8) {
                    if !modelText.isEmpty {
                        NotchMarkdownView(text: modelText, isUser: false, widthMode: .hugContent(maxWidth: 480))
                    }
                    if isModelSpeaking {
                        CaptionTypingDots()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    VisualEffectView()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: modelText)
            }
            if let toolAction {
                ToolStatusLine(action: toolAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
    }
}

private struct CaptionTypingDots: View {
    @State private var dotPhase = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.72))
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
        .padding(.bottom, 4)
    }
}

private struct ToolStatusLine: View {
    let action: ToolActionToast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(action.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.72))
        .multilineTextAlignment(.center)
    }
}

/// Image preview above caption text.
private struct CompactImageAboveCaption: View {
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

// MARK: - Window Controller

@MainActor
final class TranscriptOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TranscriptOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var hideDebounceWorkItem: DispatchWorkItem?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    /// Captured when auto-hide fires. Suppresses re-opening the panel when
    /// only extras (image/toast) clear while transcript text hasn't changed.
    private var suppressedTranscriptKey: String? = nil

    private let panelWidth: CGFloat = 520
    private let maxPanelHeight: CGFloat = 1200
    private let notchSpacing: CGFloat = 4

    /// Auto-hide waits for transcript deltas to settle, then idles before fading — keep total delay
    /// close to the fade-only path when `shouldShow` flips false so hide timing feels consistent.
    private enum HideTiming {
        static let debounceAfterLastUpdate: TimeInterval = 0.12
        static let idleBeforeFade: TimeInterval = 0.22
        /// Extra idle after the base delay when a Pexels/inline image is shown (still auto-hide, not forever).
        static let idleExtraWhenImage: TimeInterval = 2.8
        static let fadeOutDuration: TimeInterval = 0.28
        static let fadeInDuration: TimeInterval = 0.22
    }

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

        gemini.$transcriptOverlayAutoHide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.hideTask?.cancel()
                    self.hideDebounceWorkItem?.cancel()
                    self.hideDebounceWorkItem = nil
                } else if self.panel != nil, let g = self.gemini {
                    self.scheduleAutoHide(isModelSpeaking: g.overlayInput.isModelSpeaking)
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
            ctx.duration = HideTiming.fadeInDuration
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanelVisible() {
        guard let panel, panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = HideTiming.fadeInDuration
            panel.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        hideTask?.cancel()
        hideDebounceWorkItem?.cancel()
        hideDebounceWorkItem = nil
        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = HideTiming.fadeOutDuration
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
        hideDebounceWorkItem?.cancel()

        guard gemini?.transcriptOverlayAutoHide != false else { return }
        guard !isModelSpeaking else { return }

        // Transcript keeps publishing small deltas after the model stops; restarting the timer on
        // every update made the overlay feel like it “never” hid. Wait for a quiet period first.
        let item = DispatchWorkItem { [weak self] in
            self?.runHideIdleLoop()
        }
        hideDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + HideTiming.debounceAfterLastUpdate, execute: item)
    }

    private func runHideIdleLoop() {
        hideDebounceWorkItem = nil
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.gemini?.transcriptOverlayAutoHide != false else { return }
            let hasImage = self.gemini?.overlayInput.imageRequest != nil
            let idle = HideTiming.idleBeforeFade + (hasImage ? HideTiming.idleExtraWhenImage : 0)
            let ms = Int(idle * 1000)
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            self.suppressedTranscriptKey = self.gemini?.overlayInput.transcriptKey
            self.hide(animated: true)
        }
    }
}
