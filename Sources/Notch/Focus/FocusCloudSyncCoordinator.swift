import Foundation

@MainActor
protocol FocusPortalAuthenticationProviding: AnyObject {
    func freshConfiguredPortalUserConfiguration(forceRefresh: Bool) async -> PortalBackendConfiguration?
}

extension PortalAccountCoordinator: FocusPortalAuthenticationProviding {}

@MainActor
final class FocusCloudSyncCoordinator: ObservableObject {
    enum SyncState: Equatable {
        case idle
        case syncing
        case signedOut
        case failed(String)
    }

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var leaderboardOptIn = true
    @Published private(set) var displayName = ""
    @Published private(set) var weeklyRank = 0
    @Published private(set) var streakDays = 0
    @Published private(set) var leaderboardEntries: [FocusLeaderboardEntry] = []
    @Published private(set) var isFetchingLeaderboard = false
    @Published private(set) var leaderboardWindow = "week"

    private let repository: FocusDailyStatsRepository
    private let portalAccount: any FocusPortalAuthenticationProviding
    private let portalClient: any FocusPortalSyncClient
    private var syncTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private let maxSyncBatchSize = 120

    init(
        repository: FocusDailyStatsRepository,
        portalAccount: any FocusPortalAuthenticationProviding,
        portalClient: any FocusPortalSyncClient
    ) {
        self.repository = repository
        self.portalAccount = portalAccount
        self.portalClient = portalClient
        repository.onPendingDataChanged = { [weak self] in self?.scheduleSync() }
    }

    var statusText: String {
        switch state {
        case .idle:
            return repository.pendingDateKeys.isEmpty ? "Focus cloud sync is up to date." : "Focus sync pending."
        case .syncing:
            return "Syncing focus stats..."
        case .signedOut:
            return "Sign in to sync focus stats."
        case let .failed(message):
            return message
        }
    }

    func start() {
        scheduleSync(delay: .seconds(1))
        Task { await refreshProfile() }
    }

    func shutdown() {
        syncTask?.cancel()
        retryTask?.cancel()
        syncTask = nil
        retryTask = nil
    }

    func scheduleSync(delay: Duration = .seconds(2)) {
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > .zero { try? await Task.sleep(for: delay) }
            await syncPendingFocusStats()
        }
    }

    func syncPendingFocusStats() async {
        let entries = repository.pendingSnapshot(limit: maxSyncBatchSize)
        guard !entries.isEmpty else {
            state = .idle
            return
        }
        guard let configuration = await portalAccount.freshConfiguredPortalUserConfiguration(forceRefresh: false) else {
            state = .signedOut
            return
        }

        state = .syncing
        do {
            try await portalClient.focusSync(
                configuration: configuration,
                request: FocusCloudSyncRequest(schemaVersion: 2, entries: entries)
            )
            repository.acknowledgeSynced(entries)
            state = .idle
            Task { [weak self] in
                await self?.refreshProfile()
            }
            if !repository.pendingDateKeys.isEmpty { scheduleSync(delay: .zero) }
        } catch PortalAPIError.unauthorized {
            state = .signedOut
            scheduleRetry(after: .seconds(60))
        } catch {
            state = .failed("Focus sync failed. Retrying soon.")
            scheduleRetry(after: .seconds(30))
        }
    }

    func refreshProfile() async {
        guard let configuration = await portalAccount.freshConfiguredPortalUserConfiguration(forceRefresh: false) else {
            state = .signedOut
            return
        }
        do {
            let profile = try await portalClient.focusMe(configuration: configuration)
            leaderboardOptIn = profile.user.leaderboardOptIn
            displayName = profile.user.displayName ?? ""
            weeklyRank = profile.user.weeklyRank ?? 0
            streakDays = profile.user.streakDays ?? 0
        } catch {
            NotchLog.app.error("[ERROR refreshProfile] failed: \(error.localizedDescription)")
            return
        }
    }

    func updateLeaderboardProfile(optIn: Bool, displayName: String) async {
        guard let configuration = await portalAccount.freshConfiguredPortalUserConfiguration(forceRefresh: false) else {
            state = .signedOut
            return
        }
        let payload = FocusCloudProfileUpdateRequest(
            leaderboardOptIn: optIn,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        state = .syncing
        do {
            let profile = try await portalClient.updateFocusProfile(configuration: configuration, request: payload)
            leaderboardOptIn = profile.user.leaderboardOptIn
            self.displayName = profile.user.displayName ?? ""
            weeklyRank = profile.user.weeklyRank ?? 0
            streakDays = profile.user.streakDays ?? 0
            state = .idle
            scheduleSync(delay: .zero)
        } catch {
            state = .failed("Couldn't update leaderboard profile.")
        }
    }

    func fetchLeaderboard(window: String) async {
        guard let configuration = await portalAccount.freshConfiguredPortalUserConfiguration(forceRefresh: false) else {
            state = .signedOut
            return
        }

        isFetchingLeaderboard = true
        leaderboardWindow = window
        do {
            let response = try await portalClient.fetchFocusLeaderboard(configuration: configuration, window: window)
            self.leaderboardEntries = response.leaderboard
        } catch {
            NotchLog.app.error("[ERROR fetchLeaderboard] failed: \(error.localizedDescription)")
        }
        isFetchingLeaderboard = false
    }

    private func scheduleRetry(after delay: Duration) {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            await self?.syncPendingFocusStats()
        }
    }
}
