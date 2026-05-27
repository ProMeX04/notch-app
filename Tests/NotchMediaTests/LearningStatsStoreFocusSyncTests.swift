import XCTest
@testable import Notch
import NotchFocusFeature

final class LearningStatsStoreFocusSyncTests: XCTestCase {
    @MainActor
    func testLocalStatsOnlyCountsExplicitCompletedSessions() {
        let store = LearningStatsStore(repository: LearningStatsRepository(fileURL: makeLearningStatsFileURL()), calendar: Calendar(identifier: .gregorian))
        let now = Date()
        store.recordFocusedInterval(DateInterval(start: now.addingTimeInterval(-900), end: now), source: .pomodoro)
        store.recordFocusedInterval(DateInterval(start: now.addingTimeInterval(-600), end: now), source: .pomodoro)
        XCTAssertEqual(store.totalLearningSeconds, 1_500)
        XCTAssertEqual(store.totalSessions, 0)

        store.recordCompletedFocusSession(at: now, source: .pomodoro)
        XCTAssertEqual(store.totalSessions, 1)
        XCTAssertEqual(store.averageSessionSeconds, 1_500)
    }

    @MainActor
    func testRepositorySplitsFocusedIntervalAcrossUTCMidnight() {
        let repository = FocusDailyStatsRepository(fileURL: makeFileURL())
        let start = ISO8601DateFormatter().date(from: "2026-05-27T23:59:30Z")!
        repository.recordFocusedInterval(DateInterval(start: start, end: start.addingTimeInterval(90)))
        repository.recordCompletedFocusSession(at: start.addingTimeInterval(90))
        XCTAssertEqual(repository.entries["2026-05-27"]?.focusSeconds, 30)
        XCTAssertEqual(repository.entries["2026-05-27"]?.sessionCount, 0)
        XCTAssertEqual(repository.entries["2026-05-28"]?.focusSeconds, 60)
        XCTAssertEqual(repository.entries["2026-05-28"]?.sessionCount, 1)
    }

    @MainActor
    func testPendingSnapshotSurvivesReloadAndAcknowledgementDoesNotLoseConcurrentUpdate() {
        let fileURL = makeFileURL()
        let now = Date()
        let repository = FocusDailyStatsRepository(fileURL: fileURL)
        repository.recordFocusedInterval(DateInterval(start: now.addingTimeInterval(-300), end: now))
        let sent = repository.pendingSnapshot(limit: 120)

        let restoredAfterFailure = FocusDailyStatsRepository(fileURL: fileURL)
        XCTAssertEqual(restoredAfterFailure.pendingEntries, sent)

        repository.recordFocusedInterval(DateInterval(start: now, end: now.addingTimeInterval(200)))
        repository.acknowledgeSynced(sent)
        XCTAssertEqual(repository.pendingEntries.first?.focusSeconds, 500)

        repository.acknowledgeSynced(repository.pendingSnapshot(limit: 120))
        XCTAssertTrue(repository.pendingEntries.isEmpty)
    }

    @MainActor
    func testSyncWithoutAuthenticatedPortalSessionStaysPending() async {
        let repository = FocusDailyStatsRepository(fileURL: makeFileURL())
        let now = Date()
        repository.recordFocusedInterval(DateInterval(start: now.addingTimeInterval(-60), end: now))
        let coordinator = FocusCloudSyncCoordinator(
            repository: repository,
            portalAccount: SignedOutPortalContext(),
            portalClient: TestFocusPortalSyncClient()
        )

        await coordinator.syncPendingFocusStats()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertFalse(repository.pendingEntries.isEmpty)
    }

    private func makeLearningStatsFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LearningStatsStoreFocusSyncTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("learning-stats.json")
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LearningStatsStoreFocusSyncTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("daily-stats-v2.json")
    }
}

@MainActor
private final class SignedOutPortalContext: FocusPortalAuthenticationProviding {
    func freshConfiguredPortalUserConfiguration(forceRefresh: Bool) async -> PortalBackendConfiguration? {
        nil
    }
}

private final class TestFocusPortalSyncClient: FocusPortalSyncClient {
    func focusSync(configuration: PortalBackendConfiguration, request body: FocusCloudSyncRequest) async throws {}

    func focusMe(configuration: PortalBackendConfiguration) async throws -> FocusCloudMeResponse {
        FocusCloudMeResponse(user: FocusCloudUser(displayName: nil, leaderboardOptIn: false))
    }

    func updateFocusProfile(configuration: PortalBackendConfiguration, request body: FocusCloudProfileUpdateRequest) async throws -> FocusCloudProfileResponse {
        FocusCloudProfileResponse(user: FocusCloudUser(displayName: body.displayName, leaderboardOptIn: body.leaderboardOptIn))
    }
}
