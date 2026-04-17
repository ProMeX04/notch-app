import AppKit
import Combine
import SwiftUI

private struct PomodoroFullscreenView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @AppStorage("app_language") private var appLanguage: String = "English"

    @State private var backgroundPulse = false
    @State private var floatingOffset: CGFloat = 0
    @State private var currentEntry = MotivationalQuote(text: "", author: "")

    var body: some View {
        let phase = pomodoro.phase

        // Premium Color Palette
        let gradientColors: [Color] = {
            switch phase {
            // Rose / salmon-pink — not pure red (aligns with focus accent elsewhere)
            case .focus: return [
                Color(red: 0.98, green: 0.40, blue: 0.55),
                Color(red: 0.50, green: 0.13, blue: 0.26),
            ]
            case .shortBreak: return [Color(red: 0.1, green: 0.7, blue: 0.4), Color(red: 0.05, green: 0.3, blue: 0.2)]
            case .longBreak: return [Color(red: 0.1, green: 0.4, blue: 0.9), Color(red: 0.05, green: 0.2, blue: 0.5)]
            }
        }()

        ZStack {
            // Background Layer: Deep Black + Subtle Gradient
            Color.black.ignoresSafeArea()
            
            RadialGradient(colors: [gradientColors[0].opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()

            // Background Hero Icon: Large, Blurred, and Floating
            Image(systemName: phase.symbolName)
                .font(.system(size: 400))
                .foregroundStyle(gradientColors[0].opacity(0.04))
                .blur(radius: 4)
                .offset(y: floatingOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                        floatingOffset = 40
                    }
                }

            VStack(spacing: 40) {
                Spacer()
                
                // Group 1: Reminder (replaces phase label) & session status
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(currentEntry.text)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(gradientColors[0])
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        if !currentEntry.author.isEmpty {
                            Text(currentEntry.author)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(gradientColors[0].opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 680)
                    .background(
                        Capsule()
                            .fill(gradientColors[0].opacity(0.1))
                            .overlay(Capsule().stroke(gradientColors[0].opacity(0.2), lineWidth: 1))
                    )
                    .accessibilityLabel(
                        "\(Localization.get(phase.rawValue, lang: appLanguage)). \(currentEntry.text). \(currentEntry.author)"
                    )

                    HStack(spacing: 12) {
                        PomodoroSessionDotsView(
                            current: pomodoro.completedSessionsInCycle,
                            total: pomodoro.sessionsBeforeLongBreak,
                            isFocus: phase == .focus,
                            tint: gradientColors[0],
                            dotSize: 6,
                            spacing: 10,
                            indicatorSize: 12
                        )

                        Text("\(Localization.get("Round", lang: appLanguage)) \(pomodoro.currentFocusSessionIndex)/\(pomodoro.sessionsBeforeLongBreak)".uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(gradientColors[0].opacity(0.8))
                            .tracking(2)
                    }
                }

                // Group 2: The Hero Clock & Task
                VStack(spacing: 24) {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text(pomodoro.remainingText(at: context.date))
                            .font(.system(size: 180, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(gradientColors[0])
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.4), value: pomodoro.remainingSeconds)
                            .shadow(color: gradientColors[0].opacity(0.35), radius: 50, x: 0, y: 0)
                    }

                    if !pomodoro.currentTask.isEmpty {
                        VStack(spacing: 8) {
                            Text(Localization.get("Focusing on", lang: appLanguage).uppercased())
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(gradientColors[0].opacity(0.6))
                                .tracking(3)

                            HStack(spacing: 10) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(gradientColors[0])

                                Text(pomodoro.currentTask)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.05))
                                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                        }
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pomodoro.currentTask)

                Spacer()

                // Group 3: Controls
                FullscreenControlBar(pomodoro: pomodoro, accentColor: gradientColors[0])
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            if currentEntry.text.isEmpty {
                currentEntry = MotivationalQuotes.getRandom(for: pomodoro.phase, lang: appLanguage)
            }
        }
        .onChange(of: pomodoro.phase) { _, newPhase in
            withAnimation(.smooth) {
                currentEntry = MotivationalQuotes.getRandom(for: newPhase, lang: appLanguage)
            }
        }
        .onChange(of: appLanguage) { _, _ in
            currentEntry = MotivationalQuotes.getRandom(for: pomodoro.phase, lang: appLanguage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct FullscreenControlBar: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let accentColor: Color

    var body: some View {
        HStack(spacing: 32) {
            Button {
                pomodoro.skipPhase()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                pomodoro.toggleRunning()
            } label: {
                Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)

            Button {
                pomodoro.exitFullscreen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.white.opacity(0.08)))
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
    private weak var learningStats: LearningStatsStore?

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel else { return }
        let targetFrame = screen().frame
        panel.setFrame(targetFrame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: targetFrame.size)
    }

    func observe(pomodoro: PomodoroViewModel, stats: LearningStatsStore) {
        self.pomodoro = pomodoro
        self.learningStats = stats
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
        guard let pomodoro, let learningStats else { return }

        if let panel, let hv = hostingView {
            hv.rootView = PomodoroFullscreenView(pomodoro: pomodoro, learningStats: learningStats)
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

        let hv = NSHostingView(rootView: PomodoroFullscreenView(pomodoro: pomodoro, learningStats: learningStats))
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
