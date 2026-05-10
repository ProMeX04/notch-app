import AppKit
import Combine

@MainActor
final class ApplicationCoordinator {
    let environment: NotchAppEnvironment
    private let singleInstanceCoordinator: SingleInstanceCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(
        environment: NotchAppEnvironment,
        singleInstanceCoordinator: SingleInstanceCoordinator
    ) {
        self.environment = environment
        self.singleInstanceCoordinator = singleInstanceCoordinator
    }

    func start() {
        singleInstanceCoordinator.registerActivationHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.activatePrimaryWindow()
            }
        }

        environment.featureCoordinator.start()
        environment.notchController.show()
        configureJarvisBackgroundSync()
        configureAgentResultsPanel()
        configureDebugLaunchBehavior()
        refreshProStatus()
    }

    func stop() {
        cancellables.removeAll()
        singleInstanceCoordinator.unregisterActivationHandler()
        environment.featureCoordinator.stop()
        environment.focusBrowserBridgeServer.stop()
        JarvisBackgroundWindowController.shared.hide()
        AgentResultsWindowController.shared.hide()
        AgentResultStore.shared.shutdown()
        environment.notchController.shutdown()
    }

    func applicationDidBecomeActive() {
        refreshProStatus()
    }

    func screenConfigurationDidChange() {
        environment.notchController.reposition()
        JarvisBackgroundWindowController.shared.reposition()
    }

    func handle(urls: [URL]) {
        for url in urls {
            NotchCommandRouter.handle(
                url: url,
                handler: environment.featureCoordinator,
                entitlementStore: environment.entitlementStore
            )
        }
    }

    private func activatePrimaryWindow() {
        environment.notchController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureDebugLaunchBehavior() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOTCH_DEBUG_AUTOSTART_POMODORO"] == "1" else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [featureCoordinator = self.environment.featureCoordinator] in
            featureCoordinator.showFocusPanel()

            guard environment["NOTCH_DEBUG_START_PAUSED"] != "1" else { return }
            featureCoordinator.togglePomodoro()
        }
    }

    private func configureAgentResultsPanel() {
        // Touching the singleton triggers persisted load + TTL prune;
        // observing here lets the panel auto-flash when new batches arrive.
        _ = AgentResultStore.shared
        AgentResultsWindowController.shared.observeStore()
        environment.geminiLiveViewModel.$userTurnSequence
            .dropFirst()
            .sink { _ in
                AgentResultsWindowController.shared.hide()
            }
            .store(in: &cancellables)
    }

    private func configureJarvisBackgroundSync() {
        let gemini = environment.geminiLiveViewModel
        let sync: () -> Void = { [weak self] in
            self?.syncJarvisBackgroundState()
        }

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$isModelSpeaking
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$isModelThinking
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$isMicrophoneLive
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$microphoneInputLevel
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$lifecycleState
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$isMicrophoneEnabled
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$inputMode
            .sink { _ in sync() }
            .store(in: &cancellables)
        gemini.$isHoldToTalkActive
            .sink { _ in sync() }
            .store(in: &cancellables)

        syncJarvisBackgroundState()
    }

    private func syncJarvisBackgroundState() {
        let gemini = environment.geminiLiveViewModel
        let orbEnabled = JarvisTalkBackgroundOrbSettings.isEffectEnabled
        let shouldShowJarvis = orbEnabled && gemini.showsConnectedSessionUI

        guard shouldShowJarvis else {
            JarvisBackgroundWindowController.shared.setEnergyState(.idle)
            JarvisBackgroundWindowController.shared.hide()
            return
        }

        JarvisBackgroundWindowController.shared.show()
        JarvisBackgroundWindowController.shared.reloadOrbEmbeddedWebIfStoredPresetChanged()

        let state: JarvisEnergyState
        if gemini.isModelSpeaking {
            state = .speaking
        } else if gemini.isModelThinking {
            state = .thinking
        } else if gemini.isActivelyListening || (gemini.canSendLiveInput && gemini.effectiveMicrophoneEnabled) {
            state = .listening
        } else {
            state = .idle
        }

        JarvisBackgroundWindowController.shared.setEnergyState(
            state,
            signalLevel: gemini.microphoneInputLevel
        )
    }

    private func refreshProStatus() {
        Task { @MainActor [weak self] in
            await self?.environment.geminiLiveViewModel.refreshBackendSubscriptionStatus()
        }
    }
}
