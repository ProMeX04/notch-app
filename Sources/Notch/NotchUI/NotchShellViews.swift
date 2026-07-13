import AppKit
import NotchFocusFeature
import NotchShelfFeature
import SwiftUI

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
    @ObservedObject var playback: MediaProbeViewModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var talkHeaderAccessoryController: NotchHeaderAccessoryController
    let albumArtNamespace: Namespace.ID
    let shelfBrowserHost: ShelfBrowserHost

    var body: some View {
        Group {
            if presentationModel.selectedPanel == .focus {
                PomodoroPanelView(
                    pomodoro: pomodoro,
                    learningStats: learningStats,
                    focusCloudSync: focusCloudSync
                )
            } else if presentationModel.selectedPanel == .talk {
                GeminiTalkPanelView(
                    gemini: gemini,
                    entitlementStore: entitlementStore,
                    headerAccessoryController: talkHeaderAccessoryController,
                    presentationModel: presentationModel
                )
            } else if presentationModel.selectedPanel == .shelf {
                ShelfPanelView(
                    shelf: shelf,
                    presentationModel: presentationModel,
                    host: shelfBrowserHost
                )
            } else {
                HStack {
                    ExpandedAlbumArtView(
                        playback: playback,
                        albumArtNamespace: albumArtNamespace
                    )
                    .padding(.all, 5)

                    ExpandedMediaControlsView(playback: playback)
                        .drawingGroup()
                        .compositingGroup()
                }
            }
        }
        // The shelf panel hosts a heavy NSCollectionView. Pairing a sliding
        // transition with that view's first-time layout produced visible
        // jitter (collection view content laying itself out while SwiftUI
        // simultaneously moved the whole panel). A simple opacity transition
        // is cheap to render and avoids competing with NSCollectionView
        // initial layout / drop-driven inserts.
        .transition(.opacity)
    }
}
