import SwiftUI
import UniformTypeIdentifiers

private enum CompactActivity: String {
    case music
    case talk
    case pomodoro
    case countdown
    case counter
    case idle
}

struct MusicNotchView: View {
    @ObservedObject var playback: MusicProbeViewModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var countdown: CountdownViewModel
    @ObservedObject var counter: CounterViewModel
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel

    @Namespace private var albumArtNamespace
    @State private var isHovering = false
    @State private var didAutoRevealForShelfDrop = false
    @State private var didCommitShelfDrop = false
    private let shelfDropTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    private var notchAnimation: Animation {
        presentationModel.isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
            : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }

    private var topCornerRadius: CGFloat {
        presentationModel.isExpanded ? NotchMetrics.openCornerRadius.top : NotchMetrics.closedCornerRadius.top
    }

    private var bottomCornerRadius: CGFloat {
        presentationModel.isExpanded ? NotchMetrics.openCornerRadius.bottom : NotchMetrics.closedCornerRadius.bottom
    }

    private var compactActivity: CompactActivity {
        if presentationModel.selectedPanel == .talk, gemini.showCompactIndicator {
            return .talk
        }

        if playback.showCompactLiveActivity {
            return .music
        }

        return .idle
    }

    private var currentBodyWidth: CGFloat {
        if presentationModel.isExpanded {
            return NotchMetrics.openSize.width
        }

        let baseWidth = presentationModel.closedNotchSize.width

        guard compactActivity != .idle else {
            return (baseWidth - 20) + (NotchMetrics.closedCornerRadius.bottom * 2)
        }

        let sideInset = max(0, presentationModel.closedNotchSize.height - 12)
        let compactContentWidth = baseWidth + (sideInset * 2) - NotchMetrics.closedCornerRadius.top
        return compactContentWidth + (NotchMetrics.closedCornerRadius.bottom * 2)
    }

    private var currentBodyHeight: CGFloat {
        presentationModel.isExpanded ? NotchMetrics.openSize.height : presentationModel.closedNotchSize.height
    }

    private var expandedHeaderHeight: CGFloat {
        max(22, presentationModel.closedNotchSize.height - 6)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                mainLayout

                if !presentationModel.isExpanded && presentationModel.closedNotchSize.height == 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: currentBodyWidth, height: 10)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(
            maxWidth: NotchMetrics.windowSize.width,
            maxHeight: NotchMetrics.windowSize.height,
            alignment: .top
        )
        .background {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: shelfDropTypes, isTargeted: $shelf.isDropTargeted) { providers in
                    handleShelfDrop(providers)
                }
        }
        .onChange(of: shelf.isDropTargeted) { _, isTargeted in
            if isTargeted {
                didAutoRevealForShelfDrop = !presentationModel.isExpanded
                didCommitShelfDrop = false
                presentationModel.selectPanel(.shelf, reveal: true)
                return
            }

            guard didAutoRevealForShelfDrop else {
                didCommitShelfDrop = false
                return
            }

            if !didCommitShelfDrop {
                presentationModel.scheduleCollapse(after: .milliseconds(120))
            }

            didAutoRevealForShelfDrop = false
            didCommitShelfDrop = false
        }
        .compositingGroup()
        .preferredColorScheme(.dark)
    }

    private func handleShelfDrop(_ providers: [NSItemProvider]) -> Bool {
        presentationModel.selectPanel(.shelf, reveal: true)
        let accepted = shelf.handleDrop(providers: providers)
        didCommitShelfDrop = accepted
        return accepted
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            if presentationModel.isExpanded {
                NotchHeaderView(
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height,
                    presentationModel: presentationModel
                )
                .frame(height: expandedHeaderHeight)
            } else if compactActivity == .music {
                CompactLiveActivityView(
                    playback: playback,
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height,
                    albumArtNamespace: albumArtNamespace
                )
            } else if compactActivity == .pomodoro {
                CompactPomodoroView(
                    pomodoro: pomodoro,
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height
                )
            } else if compactActivity == .talk {
                CompactTalkView(
                    gemini: gemini,
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height
                )
            } else if compactActivity == .countdown {
                CompactCountdownView(
                    countdown: countdown,
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height
                )
            } else if compactActivity == .counter {
                CompactCounterView(
                    counter: counter,
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height
                )
            } else {
                IdleClosedNotchView(
                    closedNotchWidth: presentationModel.closedNotchSize.width,
                    closedNotchHeight: presentationModel.closedNotchSize.height
                )
            }

            if presentationModel.isExpanded {
                ExpandedNotchContent(
                    playback: playback,
                    pomodoro: pomodoro,
                    countdown: countdown,
                    counter: counter,
                    gemini: gemini,
                    shelf: shelf,
                    learningStats: learningStats,
                    presentationModel: presentationModel,
                    albumArtNamespace: albumArtNamespace
                )
                .padding(.top, -2)
                .padding(.horizontal, 31)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, presentationModel.isExpanded ? 0 : NotchMetrics.closedCornerRadius.bottom)
        .frame(
            width: currentBodyWidth,
            height: currentBodyHeight,
            alignment: .top
        )
        .background(.black)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.black)
                .frame(height: 1)
                .padding(.horizontal, topCornerRadius)
        }
        .overlay {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(Color.white.opacity(presentationModel.isExpanded ? 0.07 : 0.05), lineWidth: 1)
        }
        .overlay {
            if shelf.isDropTargeted {
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .stroke(Color(nsColor: .systemBlue).opacity(0.9), lineWidth: 2)
            }
        }
        .shadow(
            color: (presentationModel.isExpanded || isHovering) ? .black.opacity(0.7) : .clear,
            radius: 6
        )
        .frame(height: presentationModel.isExpanded ? NotchMetrics.openSize.height : nil)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            presentationModel.setHovering(hovering)
        }
        .onTapGesture {
            if !presentationModel.isExpanded {
                switch compactActivity {
                case .music:
                    presentationModel.selectPanel(.music)
                case .talk:
                    presentationModel.selectPanel(.talk)
                case .pomodoro:
                    presentationModel.selectedFocusTool = .pomodoro
                    presentationModel.selectPanel(.focus)
                case .countdown:
                    presentationModel.selectedFocusTool = .countdown
                    presentationModel.selectPanel(.focus)
                case .counter:
                    presentationModel.selectedFocusTool = .counter
                    presentationModel.selectPanel(.focus)
                case .idle:
                    break
                }
                presentationModel.reveal()
            }
        }
        .animation(notchAnimation, value: presentationModel.isExpanded)
        .animation(.smooth, value: compactActivity.rawValue)
        .animation(.smooth, value: presentationModel.selectedPanel.rawValue)
    }
}
