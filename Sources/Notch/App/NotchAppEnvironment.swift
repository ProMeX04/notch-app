import NotchFocusCore
@testable import NotchShelfCore
import Foundation

@MainActor
final class NotchAppEnvironment {
    let entitlementStore: NotchEntitlementStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let learningStatsStore: LearningStatsStore
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let shelfViewModel: NotchShelfViewModel
    let presentationModel: NotchPresentationModel
    let notchController: NotchWindowController
    let featureCoordinator: NotchFeatureCoordinator
    let focusBrowserBridgeServer: FocusBrowserBridgeServer

    init() {
        entitlementStore = NotchEntitlementStore()
        geminiLiveViewModel = GeminiLiveViewModel(entitlementStore: entitlementStore)
        learningStatsStore = LearningStatsStore()
        playbackViewModel = MediaProbeViewModel()
        pomodoroViewModel = PomodoroViewModel(learningStatsStore: learningStatsStore)
        focusWebsiteBlocklistStore = FocusWebsiteBlocklistStore()
        shelfViewModel = NotchShelfViewModel()
        presentationModel = NotchPresentationModel()

        notchController = NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel,
            entitlementStore: entitlementStore
        )

        featureCoordinator = NotchFeatureCoordinator(
            windowController: notchController,
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            geminiLiveViewModel: geminiLiveViewModel,
            presentationModel: presentationModel
        )

        geminiLiveViewModel.session.onNotchCommand = { [weak featureCoordinator, weak entitlementStore] urlString in
            guard let featureCoordinator = featureCoordinator,
                  let entitlementStore = entitlementStore,
                  let url = URL(string: urlString) else { return false }
            
            return await MainActor.run {
                do {
                    try NotchCommandRouter.handle(
                        url: url,
                        handler: featureCoordinator,
                        entitlementStore: entitlementStore
                    )
                    return true
                } catch {
                    return false
                }
            }
        }

        geminiLiveViewModel.session.onReadPomodoroState = { [weak pomodoroViewModel] in
            guard let pomodoroViewModel = pomodoroViewModel else {
                return ["success": false, "error": "PomodoroViewModel is not available."]
            }
            
            let isRunning = await pomodoroViewModel.isRunning
            let hasActiveSession = await pomodoroViewModel.hasActiveSession
            let phase = await pomodoroViewModel.phase.rawValue
            let remainingSeconds = await pomodoroViewModel.remainingSeconds
            let remainingText = await pomodoroViewModel.remainingText()
            let completedFocusSessions = await pomodoroViewModel.completedFocusSessions
            let currentFocusSessionIndex = await pomodoroViewModel.currentFocusSessionIndex
            let sessionsBeforeLongBreak = await pomodoroViewModel.sessionsBeforeLongBreak
            let currentTask = await pomodoroViewModel.currentTask

            return [
                "success": true,
                "isRunning": isRunning,
                "hasActiveSession": hasActiveSession,
                "phase": phase,
                "remainingSeconds": remainingSeconds,
                "remainingText": remainingText,
                "completedFocusSessions": completedFocusSessions,
                "currentFocusSessionIndex": currentFocusSessionIndex,
                "sessionsBeforeLongBreak": sessionsBeforeLongBreak,
                "currentTask": currentTask
            ]
        }

        focusBrowserBridgeServer = FocusBrowserBridgeServer(
            pomodoroViewModel: pomodoroViewModel,
            blocklistStore: focusWebsiteBlocklistStore,
            entitlementStore: entitlementStore
        )
    }
}
