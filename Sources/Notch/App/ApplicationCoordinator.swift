import AppKit
import Combine

@MainActor
final class ApplicationCoordinator {
    let environment: NotchAppEnvironment
    private let singleInstanceCoordinator: SingleInstanceCoordinator
    private let jarvisBackgroundWindowController: JarvisBackgroundWindowControlling
    private let agentResultsWindowController: AgentResultsWindowControlling
    private let agentResultStore: AgentResultStoreControlling
    private var cancellables = Set<AnyCancellable>()

    init(
        environment: NotchAppEnvironment,
        singleInstanceCoordinator: SingleInstanceCoordinator,
        jarvisBackgroundWindowController: JarvisBackgroundWindowControlling = JarvisBackgroundWindowController.shared,
        agentResultsWindowController: AgentResultsWindowControlling = AgentResultsWindowController.shared,
        agentResultStore: AgentResultStoreControlling = AgentResultStore.shared
    ) {
        self.environment = environment
        self.singleInstanceCoordinator = singleInstanceCoordinator
        self.jarvisBackgroundWindowController = jarvisBackgroundWindowController
        self.agentResultsWindowController = agentResultsWindowController
        self.agentResultStore = agentResultStore
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
        jarvisBackgroundWindowController.hide()
        agentResultsWindowController.hide()
        agentResultStore.shutdown()
        environment.notchController.shutdown()
    }

    func applicationDidBecomeActive() {
        refreshProStatus()
    }

    func screenConfigurationDidChange() {
        environment.notchController.reposition()
        jarvisBackgroundWindowController.reposition()
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
        agentResultsWindowController.observeStore()
        environment.geminiLiveViewModel.$userTurnSequence
            .dropFirst()
            .sink { [weak self] _ in
                self?.agentResultsWindowController.hide()
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
            jarvisBackgroundWindowController.setEnergyState(.idle, signalLevel: 0)
            jarvisBackgroundWindowController.hide()
            return
        }

        jarvisBackgroundWindowController.show()
        jarvisBackgroundWindowController.reloadOrbEmbeddedWebIfStoredPresetChanged()

        let energyState = Self.jarvisOrbEnergyState(for: gemini)
        jarvisBackgroundWindowController.setEnergyState(
            energyState,
            signalLevel: gemini.microphoneInputLevel
        )
    }

    private static func jarvisOrbEnergyState(for gemini: GeminiLiveViewModel) -> JarvisEnergyState {
        if gemini.isModelSpeaking {
            .speaking
        } else if gemini.isModelThinking {
            .thinking
        } else if gemini.isActivelyListening || (gemini.canSendLiveInput && gemini.effectiveMicrophoneEnabled) {
            .listening
        } else {
            .idle
        }
    }

    private func refreshProStatus() {
        Task { @MainActor [weak self] in
            await self?.environment.geminiLiveViewModel.refreshBackendSubscriptionStatus()
        }
    }
}
