import NotchFocusCore
@testable import NotchShelfCore
import SwiftUI
import UniformTypeIdentifiers

private enum CompactActivity: String {
    case media
    case talk
    case idle
}

private struct CompactActivityCandidate {
    let activity: CompactActivity
    let priority: Int
}

struct MediaNotchView: View {
    @ObservedObject var playback: MediaProbeViewModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var entitlementStore: NotchEntitlementStore

    @Namespace private var albumArtNamespace
    @StateObject private var talkHeaderAccessoryController = NotchHeaderAccessoryController()
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
        compactActivityCandidates
            .max(by: { $0.priority < $1.priority })?
            .activity ?? .idle
    }

    private var compactActivityCandidates: [CompactActivityCandidate] {
        var candidates: [CompactActivityCandidate] = []

        if gemini.showCompactIndicator {
            let talkPriority = presentationModel.selectedPanel == .talk ? 320 : 300
            candidates.append(.init(activity: .talk, priority: talkPriority))
        }

        if playback.showCompactLiveActivity {
            let musicPriority = presentationModel.selectedPanel == .media ? 220 : 200
            candidates.append(.init(activity: .media, priority: musicPriority))
        }

        candidates.append(.init(activity: .idle, priority: 0))
        return candidates
    }

    private var currentBodyWidth: CGFloat {
        if presentationModel.isExpanded {
            return NotchMetrics.openSize(for: presentationModel.selectedPanel).width
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
        presentationModel.isExpanded
            ? NotchMetrics.openHeight(for: presentationModel.selectedPanel)
            : presentationModel.closedNotchSize.height
    }

    private var expandedHeaderHeight: CGFloat {
        max(22, presentationModel.closedNotchSize.height - 6)
    }

    /// Tighter bottom inset for Talk so the live control bar sits nearer the notch bottom.
    private var expandedPanelBottomInset: CGFloat {
        if presentationModel.selectedPanel == .focus { return 0 }
        if presentationModel.selectedPanel == .talk { return 4 }
        return 12
    }

    private var showsDarkInnerNotch: Bool {
        presentationModel.selectedPanel != .focus && presentationModel.selectedPanel != .media
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
            maxWidth: NotchMetrics.windowSize(for: presentationModel.selectedPanel).width,
            maxHeight: NotchMetrics.windowSize(for: presentationModel.selectedPanel).height,
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

            if didAutoRevealForShelfDrop && !didCommitShelfDrop {
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

    @ViewBuilder
    private var closedNotchContent: some View {
        if compactActivity == .media {
            CompactLiveActivityView(
                playback: playback,
                closedNotchWidth: presentationModel.closedNotchSize.width,
                closedNotchHeight: presentationModel.closedNotchSize.height,
                albumArtNamespace: albumArtNamespace
            )
        } else if compactActivity == .talk {
            CompactTalkView(
                gemini: gemini,
                closedNotchWidth: presentationModel.closedNotchSize.width,
                closedNotchHeight: presentationModel.closedNotchSize.height
            )
        } else {
            IdleClosedNotchView(
                closedNotchWidth: presentationModel.closedNotchSize.width,
                closedNotchHeight: presentationModel.closedNotchSize.height
            )
        }
    }

    @ViewBuilder
    private var topSectionContent: some View {
        if presentationModel.isExpanded {
            NotchHeaderView(
                closedNotchWidth: presentationModel.closedNotchSize.width,
                closedNotchHeight: presentationModel.closedNotchSize.height,
                presentationModel: presentationModel,
                accessoryController: talkHeaderAccessoryController,
                entitlementStore: entitlementStore,
                gemini: gemini
            )
            .frame(height: expandedHeaderHeight)
        } else {
            closedNotchContent
        }
    }

    @ViewBuilder
    private var expandedPanelContent: some View {
        if presentationModel.isExpanded {
            ExpandedNotchContent(
                playback: playback,
                pomodoro: pomodoro,
                focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
                gemini: gemini,
                shelf: shelf,
                learningStats: learningStats,
                presentationModel: presentationModel,
                entitlementStore: entitlementStore,
                talkHeaderAccessoryController: talkHeaderAccessoryController,
                albumArtNamespace: albumArtNamespace
            )
            .padding(.top, presentationModel.selectedPanel == .focus ? (presentationModel.isFocusOverlayPresented ? 10 : 0) : 10)
            .padding(.horizontal, presentationModel.selectedPanel == .focus ? 0 : 31)
            .padding(.bottom, expandedPanelBottomInset)
        }
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            topSectionContent
            expandedPanelContent
        }
        .padding(.horizontal, presentationModel.isExpanded ? 0 : NotchMetrics.closedCornerRadius.bottom)
        .frame(
            width: currentBodyWidth,
            height: currentBodyHeight,
            alignment: .top
        )
        .background {
            ZStack {
                Color.black
                // Ambient album art blur — chỉ hiện ở music panel khi có bài phát
                if presentationModel.isExpanded
                    && presentationModel.selectedPanel == .media
                    && playback.isPlaying
                    && playback.albumArt != nil,
                    let albumArt = playback.albumArt {
                    Image(nsImage: albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.8)
                        .blur(radius: 35, opaque: true)
                        .opacity(0.25)
                }
            }
        }
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.black)
                .opacity(showsDarkInnerNotch ? 1 : 0)
                .frame(height: 1)
                .padding(.horizontal, topCornerRadius)
                .animation(.easeInOut(duration: 0.18), value: showsDarkInnerNotch)
        }
        .overlay {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(Color.white.opacity(presentationModel.isExpanded ? 0.07 : 0.05), lineWidth: 1)
        }
        .shadow(
            color: (presentationModel.isExpanded || isHovering) ? .black.opacity(0.7) : .clear,
            radius: 6
        )
        .frame(height: presentationModel.isExpanded ? NotchMetrics.openHeight(for: presentationModel.selectedPanel) : nil)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            presentationModel.setHovering(hovering)
        }
        .onTapGesture {
            if !presentationModel.isExpanded {
                switch compactActivity {
                case .media:
                    presentationModel.selectPanel(.media)
                case .talk:
                    presentationModel.selectPanel(.talk)
                case .idle:
                    break
                }
                presentationModel.reveal()
            }
        }
        .animation(notchAnimation, value: presentationModel.isExpanded)
        .animation(.smooth, value: compactActivity.rawValue)
        .animation(.smooth, value: presentationModel.selectedPanel.rawValue)
        .onChange(of: presentationModel.selectedPanel) { _, selectedPanel in
            if selectedPanel != .talk {
                talkHeaderAccessoryController.clear()
            }
        }
    }
}
