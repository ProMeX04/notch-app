import AppKit
import Foundation

@MainActor
enum PomodoroViewModelP0Tests {
    private static func makeViewModel(
        userDefaults: UserDefaults,
        clock: TestPomodoroClock,
        workspaceNotificationCenter: NotificationCenter
    ) -> PomodoroViewModel {
        let stats = LearningStatsStore(userDefaults: makeIsolatedUserDefaults(label: "learning-stats"))
        return PomodoroViewModel(
            userDefaults: userDefaults,
            learningStatsStore: stats,
            workspaceNotificationCenter: workspaceNotificationCenter,
            nowProvider: { clock.now },
            sleepHandler: { _ in
                try await Task.sleep(for: .seconds(3600))
            }
        )
    }

    static func wakeAdvancesElapsedPhaseOnce() async throws {
        let userDefaults = makeIsolatedUserDefaults(label: "wake")
        let clock = TestPomodoroClock(now: Date(timeIntervalSince1970: 1_000))
        let workspaceNotificationCenter = NotificationCenter()
        let vm = makeViewModel(
            userDefaults: userDefaults,
            clock: clock,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 5, breakSeconds: 3)
        vm.start()

        clock.now = clock.now.addingTimeInterval(6)
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await Task.sleep(for: .milliseconds(50))

        try expectEqual(vm.phase, .shortBreak)
        try expect(vm.isRunning)
        try expectEqual(vm.completedFocusSessions, 1)

        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        try expectEqual(vm.phase, .shortBreak, "wake catch-up should be idempotent")
        try expectEqual(vm.completedFocusSessions, 1)
    }

    static func restoreCatchUpMultipleExpiredPhases() async throws {
        let baseTime = Date(timeIntervalSince1970: 5_000)
        let workspaceNotificationCenter = NotificationCenter()
        let userDefaults = makeIsolatedUserDefaults(label: "restore")

        do {
            let liveClock = TestPomodoroClock(now: baseTime)
            let originalVM = makeViewModel(
                userDefaults: userDefaults,
                clock: liveClock,
                workspaceNotificationCenter: workspaceNotificationCenter
            )
            originalVM.updateCurrentDurations(focusSeconds: 10, breakSeconds: 5)
            originalVM.updateLongBreakDuration(seconds: 7)
            originalVM.updateSessionsBeforeLongBreak(count: 2)
            originalVM.start()
            originalVM.shutdown()
        }

        let restoredClock = TestPomodoroClock(now: baseTime.addingTimeInterval(30))
        let restoredVM = makeViewModel(
            userDefaults: userDefaults,
            clock: restoredClock,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        defer { restoredVM.shutdown() }

        try expectEqual(restoredVM.phase, .longBreak)
        try expect(restoredVM.isRunning)
        try expectEqual(restoredVM.completedFocusSessions, 2)
        try expectEqual(restoredVM.remainingSeconds(at: restoredClock.now), 2)
    }
}
