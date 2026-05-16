import AppKit
import Combine
import SwiftUI

// MARK: - SwiftUI View

@MainActor
final class TranscriptOverlayModel: ObservableObject {
    @Published var input: TranscriptOverlayInput?
    @Published var isVisible: Bool = false
    @Published var isPinned: Bool = false
    @Published var isHovered: Bool = false
    var onClose: (() -> Void)?

    var modelText: String {
        guard let input, input.subsEnabled else { return "" }
        return input.modelText
    }

    var isModelSpeaking: Bool {
        guard let input else { return false }
        return input.isModelSpeaking && input.subsEnabled
    }

    var toolAction: ToolActionToast? {
        input?.toolAction
    }
}

private struct TranscriptOverlayView: View {
    @ObservedObject var model: TranscriptOverlayModel
    @Environment(\.colorScheme) private var colorScheme

    private var isLightChrome: Bool { colorScheme == .light }
    private var bubbleFillColor: Color { isLightChrome ? .white.opacity(0.82) : .black.opacity(0.22) }
    private var bubbleStrokeColor: Color { isLightChrome ? .black.opacity(0.14) : .white.opacity(0.12) }
    private var closeIconColor: Color { isLightChrome ? .black.opacity(0.68) : .white.opacity(0.72) }
    private var maxBubbleHeight: CGFloat {
        min(360, (NSScreen.main?.visibleFrame.height ?? 900) * 0.42)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if (model.isVisible && !model.modelText.isEmpty) || model.isModelSpeaking {
                ScrollView(.vertical) {
                    HStack(alignment: .bottom, spacing: 8) {
                        if !model.modelText.isEmpty {
                            NotchMarkdownView(text: model.modelText, isUser: false, widthMode: .hugContent(maxWidth: 480))
                                .textSelection(.enabled)
                        }
                        if model.isModelSpeaking {
                            CaptionTypingDots()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: maxBubbleHeight)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    ZStack {
                        VisualEffectView(material: isLightChrome ? .sidebar : .hudWindow)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(bubbleFillColor)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(bubbleStrokeColor, lineWidth: 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.isPinned {
                        Button {
                            model.onClose?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(closeIconColor)
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                        .offset(x: 8, y: -8)
                        .help("Hide Captions")
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    model.isHovered = hovering
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.modelText)
            }
            if let toolAction = model.toolAction {
                ToolStatusLine(action: toolAction)
            }
        }
        .frame(width: 520)
        .padding(.top, 6)
        .padding(.bottom, 6)

    }
}

private struct CaptionTypingDots: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var dotPhase = false

    private var dotColor: Color {
        colorScheme == .light ? .black.opacity(0.62) : .white.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(dotColor)
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
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        colorScheme == .light ? .black.opacity(0.72) : .white.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(action.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(foregroundColor)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Window Controller

private final class TranscriptOverlayPanel: NSPanel { }

private final class TranscriptOverlayHostingView<Content: View>: NSHostingView<Content> { }




@MainActor
final class TranscriptOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TranscriptOverlayView>?
    private let model = TranscriptOverlayModel()
    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var hideDebounceWorkItem: DispatchWorkItem?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    /// Captured when auto-hide fires. Suppresses re-opening the panel when
    /// only transient extras clear while transcript text hasn't changed.
    private var suppressedTranscriptKey: String? = nil

    private let panelWidth: CGFloat = 520
    private let maxPanelHeight: CGFloat = 1200
    private let notchSpacing: CGFloat = 4

    /// Auto-hide waits for transcript deltas to settle, then idles before fading — keep total delay
    /// close to the fade-only path when `shouldShow` flips false so hide timing feels consistent.
    private enum HideTiming {
        static let debounceAfterLastUpdate: TimeInterval = 0.12
        static let idleBeforeFade: TimeInterval = 1.5
        static let fadeOutDuration: TimeInterval = 0.28
        static let fadeInDuration: TimeInterval = 0.22
    }

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen

        guard let panel, let hv = hostingView else { return }
        let targetFrame = panelFrame(on: screen(), height: hv.fittingSize.height)
        panel.setFrame(targetFrame, display: true)
        hv.frame = CGRect(origin: .zero, size: targetFrame.size)
    }


    func observe(gemini: GeminiLiveViewModel) {
        self.gemini = gemini
        suppressedTranscriptKey = nil
        model.input = nil
        model.isVisible = false
        model.isPinned = !gemini.transcriptOverlayAutoHide
        model.onClose = { [weak self] in
            guard let self else { return }
            self.suppressedTranscriptKey = self.gemini?.overlayInput.transcriptKey
            self.hide(animated: true)
        }
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
                self.model.isPinned = !enabled
                if !enabled {
                    self.hideTask?.cancel()
                    self.hideDebounceWorkItem?.cancel()
                    self.hideDebounceWorkItem = nil
                } else if self.panel != nil, let g = self.gemini {
                    self.scheduleAutoHide(isModelSpeaking: g.overlayInput.isModelSpeaking)
                }
            }
            .store(in: &cancellables)

        model.$isHovered
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.hideTask?.cancel()
                    self.hideDebounceWorkItem?.cancel()
                    self.hideDebounceWorkItem = nil
                } else {
                    guard let g = self.gemini, g.transcriptOverlayAutoHide else { return }
                    self.scheduleAutoHide(isModelSpeaking: g.overlayInput.isModelSpeaking)
                }
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        gemini = nil
        cancellables.removeAll()
        model.input = nil
        model.isVisible = false
        model.isPinned = false
        model.onClose = nil
        hide(animated: true)
    }

    // MARK: - Private

    private func apply(_ input: TranscriptOverlayInput) {
        // Suppress re-opening when only transient extras cleared and transcript unchanged.
        if panel == nil,
           let suppressed = suppressedTranscriptKey,
           input.transcriptKey == suppressed,
           input.toolAction == nil {
            return
        }
        suppressedTranscriptKey = nil
        model.input = input
        model.isVisible = true
        showOrUpdate()
        scheduleAutoHide(isModelSpeaking: input.isModelSpeaking)
    }

    private func screen() -> NSScreen {
        preferredScreen
        ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        ?? NSScreen.main
        ?? NSScreen.screens[0]
    }

    private func panelFrame(on screen: NSScreen, height: CGFloat) -> CGRect {
        let closedNotchHeight = NotchMetrics.baseClosedSize(for: screen).height
        let x = screen.frame.midX - panelWidth / 2
        let y = screen.frame.maxY - closedNotchHeight - notchSpacing - height
        return CGRect(x: x, y: y, width: panelWidth, height: height)
    }


    private func showOrUpdate() {
        if let panel, let hv = hostingView {
            let contentHeight = hv.fittingSize.height
            let targetFrame = panelFrame(on: screen(), height: contentHeight)
            panel.setFrame(targetFrame, display: true)
            hv.frame = CGRect(origin: .zero, size: targetFrame.size)
            ensurePanelVisible()
            return
        }

        // Create a large stable window once
        let sc = screen()
        let root = TranscriptOverlayView(model: model)
        let hv = TranscriptOverlayHostingView(rootView: root)
        let initialHeight = hv.fittingSize.height
        let frame = panelFrame(on: sc, height: initialHeight)

        let panel = TranscriptOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NotchHUDWindowLevels.aboveOrb
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Always accept mouse events: enables hover-pause + text selection. Click-through is
        // intentionally not preserved here per UX choice.
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0

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
        model.isHovered = false
        model.isVisible = false
        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = HideTiming.fadeOutDuration
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    panel.orderOut(nil)
                    self?.model.input = nil
                    self?.panel = nil
                    self?.hostingView = nil
                }
            })
        } else {
            panel.orderOut(nil)
            model.input = nil
            self.panel = nil
            self.hostingView = nil
        }
    }

    private func scheduleAutoHide(isModelSpeaking: Bool) {
        hideTask?.cancel()
        hideDebounceWorkItem?.cancel()

        guard gemini?.transcriptOverlayAutoHide != false else { return }
        guard !isModelSpeaking else { return }
        // Hover pauses the auto-hide entirely; resume happens via `model.$isHovered` sink.
        guard !model.isHovered else { return }

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
            guard !self.model.isHovered else { return }
            let ms = Int(HideTiming.idleBeforeFade * 1000)
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            guard !self.model.isHovered else { return }
            self.suppressedTranscriptKey = self.gemini?.overlayInput.transcriptKey
            self.hide(animated: true)
        }
    }
}
