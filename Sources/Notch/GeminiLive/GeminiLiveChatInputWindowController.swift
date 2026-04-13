import AppKit
import Combine
import SwiftUI

/// Accepts keyboard focus so the chat `TextField` works on a borderless panel.
private final class GeminiLiveChatKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}

// MARK: - Drag handle (reliable on floating panels)

private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .menu
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct GeminiLiveChatInputContentView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .onSubmit(commitSend)
                .disabled(gemini.connectionState != .connected)

            Button(action: commitSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.2 : 0.95))
            }
            .buttonStyle(.plain)
            .disabled(
                gemini.connectionState != .connected
                    || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .focusEffectDisabled()
        .background {
            VisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private func commitSend() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard gemini.sendLiveChatMessage(trimmed) else { return }
        draft = ""
    }
}

// MARK: - Window controller

@MainActor
final class GeminiLiveChatInputWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<GeminiLiveChatInputContentView>?
    private var cancellables = Set<AnyCancellable>()
    private var moveObserver: NSObjectProtocol?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    private let panelWidth: CGFloat = 340
    private let panelHeight: CGFloat = 56
    private let defaultsKey = "dev.notch.gemini-live-chat-input.frame"

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel, hostingView != nil else { return }
        if !frameIntersectsAnyVisibleWorkspace(panel.frame) {
            let sc = screenForPlacement()
            let target = clampFrame(panel.frame, to: sc)
            panel.setFrame(target, display: true)
            hostingView?.frame = CGRect(origin: .zero, size: target.size)
        }
    }

    func observe(gemini: GeminiLiveViewModel) {
        self.gemini = gemini
        cancellables.removeAll()

        Publishers.CombineLatest(gemini.$connectionState, gemini.$showLiveChatInput)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, showInput in
                guard let self else { return }
                if state == .connected, showInput {
                    self.ensurePanel(gemini: gemini)
                    self.panel?.orderFrontRegardless()
                } else {
                    self.panel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        gemini = nil
        cancellables.removeAll()
        removeMoveObserver()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Private

    private func screenForPlacement() -> NSScreen {
        preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func defaultFrame(on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let x = vf.midX - panelWidth / 2
        let y = vf.minY + 72
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveFrame(_ frame: CGRect) {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height],
            forKey: defaultsKey
        )
    }

    private func dominantScreen(forWindowFrame windowFrame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.frame)
            let area = max(0, inter.width) * max(0, inter.height)
            if area > bestArea {
                bestArea = area
                best = s
            }
        }
        return best
    }

    private func clampFrame(_ frame: CGRect, to screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var f = frame
        let minVisible: CGFloat = 48
        f.origin.x = min(max(f.origin.x, vf.minX - f.width + minVisible), vf.maxX - minVisible)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - minVisible)
        return f
    }

    private func frameIntersectsAnyVisibleWorkspace(_ windowFrame: CGRect) -> Bool {
        let minOverlap: CGFloat = 32
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.visibleFrame)
            if inter.width >= minOverlap, inter.height >= minOverlap {
                return true
            }
        }
        return false
    }

    private func removeMoveObserver() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
    }

    private func ensurePanel(gemini: GeminiLiveViewModel) {
        let sc = screenForPlacement()

        if let hv = hostingView {
            hv.rootView = GeminiLiveChatInputContentView(gemini: gemini)
            return
        }

        let saved = loadSavedFrame()
        let initial: CGRect
        if let saved {
            let onScreen = dominantScreen(forWindowFrame: saved) ?? sc
            initial = clampFrame(saved, to: onScreen)
        } else {
            initial = defaultFrame(on: sc)
        }

        let panel = GeminiLiveChatKeyPanel(
            contentRect: initial,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        let root = GeminiLiveChatInputContentView(gemini: gemini)
        let hv = NSHostingView(rootView: root)
        hv.frame = CGRect(origin: .zero, size: initial.size)
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        let trackedWindowNumber = panel.windowNumber
        removeMoveObserver()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let w = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self.saveFrame(w.frame)
            }
        }
    }
}
