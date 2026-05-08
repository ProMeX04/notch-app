import AppKit
import Combine
import SwiftUI

private final class GeminiExecApprovalPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct GeminiExecApprovalPanelContentView: View {
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        Group {
            if let approval = gemini.currentPendingExecApproval {
                VStack(alignment: .leading, spacing: 14) {
                    GeminiExecApprovalCard(
                        request: approval,
                        queueCount: gemini.pendingExecApprovals.count,
                        onApproveOnce: { gemini.approveCurrentExecApprovalOnce() },
                        onApproveExact: { gemini.approveCurrentExecApprovalExact() },
                        onApproveFamily: { gemini.approveCurrentExecApprovalFamily() },
                        onDeny: { gemini.denyCurrentExecApproval() }
                    )
                }
                .padding(14)
                .background {
                    GeminiExecApprovalPanelMaterial()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
            } else {
                EmptyView()
            }
        }
        .frame(width: 520)
    }
}

private struct GeminiExecApprovalPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
final class GeminiExecApprovalPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<GeminiExecApprovalPanelContentView>?
    private var cancellables = Set<AnyCancellable>()
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    private let panelWidth: CGFloat = 548
    private let panelHeight: CGFloat = 170

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel, hostingView != nil else { return }
        let target = defaultFrame(on: screenForPlacement())
        panel.setFrame(target, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: target.size)
    }

    func observe(gemini: GeminiLiveViewModel) {
        self.gemini = gemini
        cancellables.removeAll()

        gemini.$pendingExecApprovals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] approvals in
                guard let self else { return }
                if approvals.isEmpty {
                    self.panel?.orderOut(nil)
                    return
                }
                self.ensurePanel(gemini: gemini)
                self.panel?.orderFrontRegardless()
            }
            .store(in: &cancellables)
    }

    func present(gemini: GeminiLiveViewModel) {
        ensurePanel(gemini: gemini)
        panel?.orderFrontRegardless()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func stopObserving() {
        gemini = nil
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    private func screenForPlacement() -> NSScreen {
        preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func defaultFrame(on screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panelWidth / 2
        let y = visibleFrame.maxY - panelHeight - 92
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func ensurePanel(gemini: GeminiLiveViewModel) {
        let targetFrame = defaultFrame(on: screenForPlacement())

        if let hostingView {
            hostingView.rootView = GeminiExecApprovalPanelContentView(gemini: gemini)
            panel?.setFrame(targetFrame, display: true)
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
            return
        }

        let panel = GeminiExecApprovalPanelWindow(
            contentRect: targetFrame,
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

        let rootView = GeminiExecApprovalPanelContentView(gemini: gemini)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }
}
