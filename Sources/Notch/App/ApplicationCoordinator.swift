import AppKit

@MainActor
final class ApplicationCoordinator {
    let environment: NotchAppEnvironment
    private let singleInstanceCoordinator: SingleInstanceCoordinator

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
        configureDebugLaunchBehavior()
        refreshProStatus()
    }

    func stop() {
        singleInstanceCoordinator.unregisterActivationHandler()
        environment.featureCoordinator.stop()
        environment.focusBrowserBridgeServer.stop()
        environment.notchController.shutdown()
    }

    func applicationDidBecomeActive() {
        refreshProStatus()
    }

    func screenConfigurationDidChange() {
        environment.notchController.reposition()
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

    private func refreshProStatus() {
        Task { @MainActor [weak self] in
            await self?.environment.geminiLiveViewModel.refreshBackendSubscriptionStatus()
        }
    }
}
