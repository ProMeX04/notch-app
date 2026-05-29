import NotchFocusFeature
import NotchShelfFeature
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
    let screenID: NotchScreenID

    @Namespace private var albumArtNamespace
    @StateObject private var talkHeaderAccessoryController = NotchHeaderAccessoryController()
    // Persistent host for the shelf NSCollectionView. By owning it here
    // (rather than letting `ShelfBrowserView` recreate it on every panel
    // reveal) the underlying AppKit view stays alive across panel
    // switches and notch collapse/expand cycles, which removes the most
    // visible source of drag-and-drop "khựng".
    @StateObject private var shelfBrowserHost = ShelfBrowserHost()
    @State private var isHovering = false
    @State private var isShelfDropTargeted = false
    private let minimumClosedVisualHeight: CGFloat = 20

    init(
        playback: MediaProbeViewModel,
        pomodoro: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        gemini: GeminiLiveViewModel,
        shelf: NotchShelfViewModel,
        learningStats: LearningStatsStore,
        presentationModel: NotchPresentationModel,
        entitlementStore: NotchEntitlementStore,
        screenID: NotchScreenID
    ) {
        self.playback = playback
        self.pomodoro = pomodoro
        self.focusWebsiteBlocklistStore = focusWebsiteBlocklistStore
        self.gemini = gemini
        self.shelf = shelf
        self.learningStats = learningStats
        self.presentationModel = presentationModel
        self.entitlementStore = entitlementStore
        self.screenID = screenID
    }
    @State private var didAutoRevealForShelfDrop = false
    @State private var didCommitShelfDrop = false
    /// Set briefly while the user's drag-into-notch is being honoured.
    /// While true, every animation modifier in this view collapses to
    /// "no animation" — the notch SNAPS to its expanded layout instead
    /// of springing into it. The spring chase used to make the drop
    /// target dance under the cursor for ~420 ms, which was the dominant
    /// source of perceived jitter.
    @State private var isDragRevealing = false
    private let shelfDropTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    private var notchAnimation: Animation? {
        if isDragRevealing { return nil }
        return isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
            : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }

    private var isExpanded: Bool {
        presentationModel.isExpanded(on: screenID)
    }

    private var closedNotchSize: CGSize {
        presentationModel.closedNotchSize(for: screenID)
    }

    private var topCornerRadius: CGFloat {
        if isExpanded { return NotchMetrics.openCornerRadius.top }
        return min(NotchMetrics.closedCornerRadius.top, closedNotchSize.height / 2)
    }

    private var bottomCornerRadius: CGFloat {
        if isExpanded { return NotchMetrics.openCornerRadius.bottom }
        return min(NotchMetrics.closedCornerRadius.bottom, closedNotchSize.height / 2)
    }

    private var compactActivity: CompactActivity {
        guard shouldRenderClosedContent else { return .idle }
        return compactActivityCandidates
            .max(by: { $0.priority < $1.priority })?
            .activity ?? .idle
    }

    private var shouldRenderClosedContent: Bool {
        isExpanded || closedNotchSize.height >= minimumClosedVisualHeight
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
        if isExpanded {
            return NotchMetrics.openSize(for: presentationModel.selectedPanel).width
        }

        let baseWidth = closedNotchSize.width
        let widthBottomRadius = NotchMetrics.closedCornerRadius.bottom

        guard compactActivity != .idle else {
            return (baseWidth - 20) + (widthBottomRadius * 2)
        }

        let standardClosedHeight: CGFloat = 30
        let sideInset = max(0, standardClosedHeight - 12)
        let compactContentWidth = baseWidth + (sideInset * 2) - NotchMetrics.closedCornerRadius.top
        return compactContentWidth + (widthBottomRadius * 2)
    }

    private var currentBodyHeight: CGFloat {
        isExpanded
            ? NotchMetrics.openHeight(for: presentationModel.selectedPanel)
            : closedNotchSize.height
    }

    private var currentContentWidth: CGFloat {
        if isExpanded { return currentBodyWidth }
        return max(0, currentBodyWidth - (bottomCornerRadius * 2))
    }

    private var expandedHeaderHeight: CGFloat {
        max(22, closedNotchSize.height - 6)
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

    private var isClosedNotchInvisible: Bool {
        guard !isExpanded else { return false }
        switch presentationModel.selectedInvisibilityMode {
        case .off:
            return false
        case .fullscreenOnly:
            return presentationModel.isFullscreenActive(on: screenID)
        case .always:
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                mainLayout

                if !isExpanded && closedNotchSize.height == 0 {
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
                .onDrop(
                    of: shelfDropTypes,
                    delegate: MediaNotchDropDelegate(
                        shelf: shelf,
                        presentationModel: presentationModel,
                        shelfBrowserHost: shelfBrowserHost,
                        isTargeted: $isShelfDropTargeted,
                        didAutoRevealForShelfDrop: $didAutoRevealForShelfDrop,
                        didCommitShelfDrop: $didCommitShelfDrop,
                        isExpanded: isExpanded,
                        snapToShelf: { self.snapToShelf() }
                    )
                )
        }
        .transaction { transaction in
            // Whenever a drag-reveal is in flight, force every animation
            // in the subtree (frames, paddings, transitions, shadow flips)
            // to apply instantaneously. The single-frame snap is the only
            // way to give the user a stable drop target while their drag
            // is in progress.
            if isDragRevealing {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
        .compositingGroup()
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    /// Reveal the shelf instantly (no spring) so the user's drag can land
    /// on a stable, fully-expanded drop target. We flip the gating flag
    /// FIRST so SwiftUI's `.animation(notchAnimation, value:)` modifier
    /// resolves to `nil` for this state change. Wrapping the mutation in
    /// a `disablesAnimations` transaction is belt-and-suspenders for any
    /// implicit animations in the chain (transitions, padding changes,
    /// shadow toggles, …).
    private func snapToShelf() {
        isDragRevealing = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentationModel.selectPanel(.shelf, on: screenID, reveal: true)
        }
        // Restore the spring on the next runloop tick so subsequent
        // click-driven panel/expand changes still feel lively.
        DispatchQueue.main.async {
            isDragRevealing = false
        }
    }

    @ViewBuilder
    private var closedNotchContent: some View {
        if !shouldRenderClosedContent {
            Rectangle()
                .fill(Color.black.opacity(0.01))
                .frame(
                    width: closedNotchSize.width,
                    height: closedNotchSize.height
                )
        } else if compactActivity == .media {
            CompactLiveActivityView(
                playback: playback,
                closedNotchWidth: closedNotchSize.width,
                closedNotchHeight: closedNotchSize.height,
                contentWidth: currentContentWidth,
                albumArtNamespace: albumArtNamespace
            )
        } else if compactActivity == .talk {
            CompactTalkView(
                gemini: gemini,
                closedNotchWidth: closedNotchSize.width,
                closedNotchHeight: closedNotchSize.height,
                contentWidth: currentContentWidth
            )
        } else {
            IdleClosedNotchView(
                closedNotchWidth: closedNotchSize.width,
                closedNotchHeight: closedNotchSize.height
            )
        }
    }

    @ViewBuilder
    private var topSectionContent: some View {
        if isExpanded {
            NotchHeaderView(
                closedNotchWidth: closedNotchSize.width,
                closedNotchHeight: closedNotchSize.height,
                presentationModel: presentationModel,
                accessoryController: talkHeaderAccessoryController,
                entitlementStore: entitlementStore,
                pomodoro: pomodoro,
                gemini: gemini
            )
            .frame(height: expandedHeaderHeight)
        } else if isClosedNotchInvisible {
            Rectangle()
                .fill(Color.black.opacity(0.01))
                .frame(
                    width: closedNotchSize.width,
                    height: closedNotchSize.height
                )
        } else {
            closedNotchContent
        }
    }

    @ViewBuilder
    private var expandedPanelContent: some View {
        if isExpanded {
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
                albumArtNamespace: albumArtNamespace,
                shelfBrowserHost: shelfBrowserHost
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
        .padding(.horizontal, isExpanded ? 0 : bottomCornerRadius)
        .frame(
            width: currentBodyWidth,
            height: currentBodyHeight,
            alignment: .top
        )
        .background {
            Color.black
        }
        .opacity(isClosedNotchInvisible ? (isHovering ? 0.12 : 0.01) : 1)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.black)
                .opacity(showsDarkInnerNotch && !isClosedNotchInvisible ? 1 : 0)
                .frame(height: 1)
                .padding(.horizontal, topCornerRadius)
                .animation(.easeInOut(duration: 0.18), value: showsDarkInnerNotch)
                .allowsHitTesting(false)
        }
        .overlay {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(Color.white.opacity(isClosedNotchInvisible ? 0 : (isExpanded ? 0.07 : 0.05)), lineWidth: 1)
            .allowsHitTesting(false)
        }
        .shadow(
            color: (isExpanded || (isHovering && !isClosedNotchInvisible)) ? .black.opacity(0.7) : .clear,
            radius: 6
        )
        .animation(.easeInOut(duration: 0.22), value: isHovering)
        .frame(height: isExpanded ? NotchMetrics.openHeight(for: presentationModel.selectedPanel) : nil)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            presentationModel.setHovering(hovering, on: screenID)
        }
        .onTapGesture {
            if !isExpanded {
                switch compactActivity {
                case .media:
                    presentationModel.selectPanel(.media, on: screenID)
                case .talk:
                    presentationModel.selectPanel(.talk, on: screenID)
                case .idle:
                    break
                }
                presentationModel.reveal(on: screenID)
            }
        }
        .animation(notchAnimation, value: isExpanded)
        .animation(isDragRevealing ? nil : .smooth, value: compactActivity.rawValue)
        .animation(isDragRevealing ? nil : .smooth, value: presentationModel.selectedPanel.rawValue)
        .onChange(of: presentationModel.selectedPanel) { _, selectedPanel in
            if selectedPanel != .talk {
                talkHeaderAccessoryController.clear()
            }
        }
    }
}

struct MediaNotchDropDelegate: DropDelegate {
    let shelf: NotchShelfViewModel
    let presentationModel: NotchPresentationModel
    let shelfBrowserHost: ShelfBrowserHost
    var isTargeted: Binding<Bool>
    var didAutoRevealForShelfDrop: Binding<Bool>
    var didCommitShelfDrop: Binding<Bool>
    let isExpanded: Bool
    let snapToShelf: () -> Void

    func dropEntered(info: DropInfo) {
        print("--- MediaNotchDropDelegate.dropEntered ---")
        isTargeted.wrappedValue = true
        shelf.isDropTargeted = true
        presentationModel.cancelScheduledCollapse()
        
        let alreadyOnShelf = presentationModel.selectedPanel == .shelf && isExpanded
        if !alreadyOnShelf {
            didAutoRevealForShelfDrop.wrappedValue = !isExpanded
            didCommitShelfDrop.wrappedValue = false
            snapToShelf()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        presentationModel.cancelScheduledCollapse()
        if isTargeted.wrappedValue && presentationModel.selectedPanel == .shelf && isExpanded {
            shelfBrowserHost.updateDropIndicator(at: info.location)
        } else {
            shelfBrowserHost.hideDropIndicator()
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        print("--- MediaNotchDropDelegate.dropExited ---")
        isTargeted.wrappedValue = false
        shelf.isDropTargeted = false
        shelfBrowserHost.hideDropIndicator()
        
        if didAutoRevealForShelfDrop.wrappedValue && !didCommitShelfDrop.wrappedValue {
            presentationModel.scheduleCollapse(after: .milliseconds(120))
        }
        didAutoRevealForShelfDrop.wrappedValue = false
        didCommitShelfDrop.wrappedValue = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL, .url, .utf8PlainText, .plainText, .data])
        print("--- MediaNotchDropDelegate.performDrop: itemProviders count = \(providers.count) ---")
        
        let isInternalDrag = providers.contains { provider in
            provider.hasItemConformingToTypeIdentifier(NotchShelfItem.internalDragIdentityTypeIdentifier)
        }
        
        // Read the target index FIRST before clearing/hiding the indicator (which resets dropTargetIndex to nil)
        let targetIndex = shelfBrowserHost.pendingDropIndex ?? 0
        print("--- MediaNotchDropDelegate.performDrop: targetIndex = \(targetIndex) ---")
        
        // Check if we are performing an internal reorder!
        let internalIDs = shelfBrowserHost.draggedItemIDs
        if !internalIDs.isEmpty {
            print("--- MediaNotchDropDelegate.performDrop: Processing internal reorder of items: \(internalIDs) to targetIndex = \(targetIndex) ---")
            
            shelf.moveItems(with: internalIDs, to: targetIndex)
            
            shelfBrowserHost.draggedItemIDs = []
            shelfBrowserHost.hideDropIndicator()
            isTargeted.wrappedValue = false
            shelf.isDropTargeted = false
            presentationModel.cancelScheduledCollapse()
            didCommitShelfDrop.wrappedValue = true
            return true
        }
        
        shelfBrowserHost.hideDropIndicator()
        isTargeted.wrappedValue = false
        shelf.isDropTargeted = false
        presentationModel.cancelScheduledCollapse()
        
        if isInternalDrag {
            print("--- MediaNotchDropDelegate.performDrop: Rejecting internal drag ---")
            return false
        }
        
        let accepted = shelf.handleDrop(providers: providers, atIndex: targetIndex)
        didCommitShelfDrop.wrappedValue = accepted
        return accepted
    }
}
