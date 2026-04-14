import AppKit
import Combine
import SwiftUI

private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct PomodoroFullscreenView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 16) {
                    Image(systemName: pomodoro.phase.symbolName)
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(Color(nsColor: pomodoro.phase.accentColor))
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 90, alignment: .center)
                    
                    Text(Localization.get(pomodoro.phase.rawValue, lang: appLanguage).uppercased())
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(4)

                    Text((Localization.get("Round", lang: appLanguage) + " \(pomodoro.currentFocusSessionIndex)/\(pomodoro.sessionsBeforeLongBreak)").uppercased())
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(2)
                }
                
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text(pomodoro.remainingText(at: context.date))
                        .font(.system(size: 120, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(nsColor: pomodoro.phase.accentColor))
                }

                FullscreenControlBar(pomodoro: pomodoro, opacityProvider: 0.5)
                    .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct FullscreenControlBar: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let opacityProvider: Double

    var body: some View {
        HStack(spacing: 24) {
            Button {
                pomodoro.skipPhase()
            } label: {
                Text("Skip")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(opacityProvider + 0.1))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(opacityProvider * 0.15)))
                    .overlay(Capsule().stroke(Color.white.opacity(opacityProvider * 0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                pomodoro.toggleRunning()
            } label: {
                Text(pomodoro.isRunning ? "Pause" : "Resume")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.85)))
            }
            .buttonStyle(.plain)

            Button {
                pomodoro.exitFullscreen()
            } label: {
                Text("Exit")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(opacityProvider + 0.1))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(opacityProvider * 0.15)))
                    .overlay(Capsule().stroke(Color.white.opacity(opacityProvider * 0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
final class PomodoroFullscreenWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<PomodoroFullscreenView>?
    private var cancellables = Set<AnyCancellable>()
    private weak var preferredScreen: NSScreen?
    private weak var pomodoro: PomodoroViewModel?

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel else { return }
        let targetFrame = screen().frame
        panel.setFrame(targetFrame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: targetFrame.size)
    }

    func observe(pomodoro: PomodoroViewModel) {
        self.pomodoro = pomodoro
        cancellables.removeAll()

        Publishers.CombineLatest(pomodoro.$isFullscreenActive, pomodoro.$focusMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFullscreenActive, mode in
                guard let self else { return }
                if isFullscreenActive && mode != .off {
                    self.showFullscreen()
                } else {
                    self.hideFullscreen()
                }
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        pomodoro = nil
        cancellables.removeAll()
        hideFullscreen()
    }

    private func screen() -> NSScreen {
        preferredScreen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showFullscreen() {
        guard let pomodoro else { return }

        if let panel, let hv = hostingView {
            hv.rootView = PomodoroFullscreenView(pomodoro: pomodoro)
            let frame = screen().frame
            panel.setFrame(frame, display: true)
            hv.frame = CGRect(origin: .zero, size: frame.size)
            ensurePanelVisible()
            return
        }

        let frame = screen().frame
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let hv = NSHostingView(rootView: PomodoroFullscreenView(pomodoro: pomodoro))
        hv.frame = CGRect(origin: .zero, size: frame.size)
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanelVisible() {
        guard let panel, panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    private func hideFullscreen() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.panel = nil
                self?.hostingView = nil
            }
        })
    }
}
