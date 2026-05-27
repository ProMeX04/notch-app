import Foundation
import NotchFocusFeature

@MainActor
struct GeminiLiveFeatureBridge {
    let geminiLiveViewModel: GeminiLiveViewModel
    let featureCoordinator: NotchFeatureCoordinator
    let entitlementStore: NotchEntitlementStore
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusBrowserBridgeServer: FocusBrowserBridgeServer

    func install() {
        let session = geminiLiveViewModel.session

        session.onNotchCommand = { [weak featureCoordinator, weak entitlementStore] urlString in
            guard let featureCoordinator,
                  let entitlementStore,
                  let url = URL(string: urlString) else { return false }

            return await MainActor.run {
                NotchCommandRouter.handle(
                    url: url,
                    handler: featureCoordinator,
                    entitlementStore: entitlementStore
                )
                return true
            }
        }

        session.onMediaCommand = { [weak featureCoordinator, weak entitlementStore] action, params in
            guard let featureCoordinator, let entitlementStore else { return false }
            return await MainActor.run {
                do {
                    try NotchCommandRouter.handleMedia(
                        action: action,
                        queryItems: params,
                        handler: featureCoordinator,
                        entitlementStore: entitlementStore
                    )
                    return true
                } catch {
                    return false
                }
            }
        }

        session.onReadMediaState = { [weak playbackViewModel] in
            guard let playbackViewModel else {
                return ["success": false, "error": "MediaProbeViewModel is not available."]
            }
            let state = await playbackViewModel.state
            return [
                "success": true,
                "isPlaying": state.isPlaying,
                "title": state.title,
                "artist": state.artist,
                "album": state.album,
                "duration": state.duration,
                "currentTime": state.currentTime,
                "volume": state.volume,
                "bundleIdentifier": state.bundleIdentifier
            ]
        }

        session.onReadPomodoroState = { [weak pomodoroViewModel] in
            guard let pomodoroViewModel else {
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

        let userStore = geminiLiveViewModel.toolingController.userStore
        let memoryStore = geminiLiveViewModel.toolingController.memoryStore
        session.onReadUserStore = { [weak userStore] in
            userStore?.readUserProfile() ?? ""
        }
        session.onReadMemoryStore = { [weak memoryStore] in
            memoryStore?.readMainMemory() ?? ""
        }
        session.onWriteUserStore = { [weak geminiLiveViewModel, weak userStore] content in
            guard let vm = geminiLiveViewModel, let userStore else { return false }
            do {
                try userStore.saveUserProfile(content)
                await MainActor.run { vm.userProfileContent = content }
                return true
            } catch {
                return false
            }
        }
        session.onWriteMemoryStore = { [weak geminiLiveViewModel, weak memoryStore] content in
            guard let vm = geminiLiveViewModel, let memoryStore else { return false }
            do {
                try memoryStore.saveMemory(content)
                await MainActor.run { vm.memoryContent = content }
                return true
            } catch {
                return false
            }
        }

        session.onBrowserBridgeCommand = { [weak focusBrowserBridgeServer] action, args in
            await focusBrowserBridgeServer?.enqueueBrowserCommand(action: action, args: args)
        }
        session.onBrowserBridgeIsConnected = { [weak focusBrowserBridgeServer] in
            focusBrowserBridgeServer?.isExtensionConnected ?? false
        }
    }
}
