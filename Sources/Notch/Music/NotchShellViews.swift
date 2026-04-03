import SwiftUI
struct CompactSpectrumView: View {
    let accentColor: Color
    let isPlaying: Bool

    var body: some View {
        Rectangle()
            .fill(accentColor.gradient)
            .mask {
                AudioSpectrumView(isPlaying: isPlaying)
                    .frame(width: 16, height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotchHeaderView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    @ObservedObject var presentationModel: NotchPresentationModel

    private var displayHeight: CGFloat {
        max(22, closedNotchHeight - 6)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                EmptyView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .offset(y: 3)

            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth, height: displayHeight)
                .mask {
                    NotchShape()
                }

            HStack(spacing: 4) {
                PanelSwitcher(presentationModel: presentationModel)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .offset(y: 3)
        }
    }
}

struct CompactLiveActivityView: View {
    @ObservedObject var playback: MusicProbeViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let albumArtNamespace: Namespace.ID

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: playback.albumArt)
                .resizable()
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            CompactSpectrumView(
                accentColor: playback.hasTrack ? Color(nsColor: playback.accentColor) : .gray,
                isPlaying: playback.isPlaying
            )
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactPomodoroView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private var accentColor: Color {
        Color(nsColor: pomodoro.phase.accentColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor.gradient)

                Image(systemName: pomodoro.phase.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .overlay {
                    HStack {
                        Spacer(minLength: 0)

                        PomodoroTimeText(
                            pomodoro: pomodoro,
                            size: 12,
                            weight: .semibold
                        )
                        .foregroundStyle(.white)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            ZStack {
                Circle()
                    .fill(accentColor.opacity(pomodoro.isRunning ? 0.18 : 0.1))

                Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactTalkView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private var accentColor: Color {
        Color(nsColor: gemini.compactAccentColor).ensureMinimumBrightness(factor: 0.74)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor.opacity(0.18))

                    Image(systemName: gemini.compactSymbolName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: sideSize, height: sideSize)

                if gemini.isScreenSharingEnabled {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen).ensureMinimumBrightness(factor: 0.72).opacity(0.85))
                }
            }

            Rectangle()
                .fill(.black)
                .overlay {
                    HStack(spacing: 8) {
                        if !gemini.compactStatusText.isEmpty {
                            Text(gemini.compactStatusText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }

                        CompactTalkPulseView(
                            tint: accentColor,
                            isAnimated: gemini.isModelSpeaking
                        )
                    }
                    .padding(.horizontal, 10)
                }
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactCountdownView: View {
    @ObservedObject var countdown: CountdownViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private let accentColor = Color(nsColor: .systemTeal)

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor.gradient)

                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .overlay {
                    HStack {
                        Spacer(minLength: 0)

                        CountdownTimeText(
                            countdown: countdown,
                            size: 12,
                            weight: .semibold
                        )
                        .foregroundStyle(.white)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            ZStack {
                Circle()
                    .fill(accentColor.opacity(countdown.isRunning ? 0.18 : 0.1))

                Image(systemName: countdown.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactTalkPulseView: View {
    let tint: Color
    let isAnimated: Bool

    var body: some View {
        if isAnimated {
            AnimatedPulseBars(tint: tint)
        } else {
            StaticPulseBars(tint: tint)
        }
    }
}

struct StaticPulseBars: View {
    let tint: Color
    private let heights: [CGFloat] = [5, 9, 6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.35))
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
    }
}

struct AnimatedPulseBars: View {
    let tint: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: 3, height: phase ? [10, 5, 12][index] : [5, 11, 7][index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}

struct IdleClosedNotchView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: closedNotchWidth, height: closedNotchHeight)
    }
}

struct ExpandedNotchContent: View {
    @ObservedObject var playback: MusicProbeViewModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var countdown: CountdownViewModel
    @ObservedObject var counter: CounterViewModel
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if presentationModel.selectedPanel == .focus {
                VStack(spacing: 6) {
                    HStack {
                        FocusToolSwitcher(presentationModel: presentationModel)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if presentationModel.selectedFocusTool == .pomodoro {
                        PomodoroPanelView(
                            pomodoro: pomodoro,
                            learningStats: learningStats
                        )
                    } else if presentationModel.selectedFocusTool == .countdown {
                        CountdownPanelView(countdown: countdown)
                    } else {
                        CounterPanelView(counter: counter)
                    }
                }
            } else if presentationModel.selectedPanel == .talk {
                GeminiTalkPanelView(gemini: gemini)
            } else if presentationModel.selectedPanel == .shelf {
                ShelfPanelView(shelf: shelf)
            } else {
                HStack {
                    ExpandedAlbumArtView(
                        playback: playback,
                        albumArtNamespace: albumArtNamespace
                    )
                    .padding(.all, 5)

                    ExpandedMusicControlsView(playback: playback)
                        .drawingGroup()
                        .compositingGroup()
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct PanelSwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel

    var body: some View {
        HStack(spacing: 3) {
            switcherButton(
                icon: "playpause",
                panel: .music
            )
            switcherButton(
                icon: "timer",
                panel: .focus
            )
            switcherButton(
                icon: "waveform.and.mic",
                panel: .talk
            )
            switcherButton(
                icon: "tray.full",
                panel: .shelf
            )
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func switcherButton(icon: String, panel: NotchPanel) -> some View {
        return Button {
            presentationModel.selectPanel(panel)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Capsule()
                        .fill(presentationModel.selectedPanel == panel ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(switcherTitle(for: panel))
    }

    private func switcherTitle(for panel: NotchPanel) -> String {
        switch panel {
        case .music:
            return "Media"
        case .focus:
            return "Focus"
        case .talk:
            return "Talk"
        case .shelf:
            return ""
        }
    }
}
