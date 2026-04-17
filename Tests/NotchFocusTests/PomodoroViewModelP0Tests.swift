import AppKit
import Foundation
import NotchFocusCore

@MainActor
enum PomodoroViewModelTests {
    private static func makeViewModel(
        userDefaults: UserDefaults,
        clock: TestPomodoroClock,
        workspaceNotificationCenter: NotificationCenter
    ) -> PomodoroViewModel {
        let stats = TestLearningStatsRecorder()
        let languageProvider = AppLanguageProvider(userDefaults: userDefaults)
        return PomodoroViewModel(
            userDefaults: userDefaults,
            learningStatsRecorder: stats,
            appLanguageProvider: languageProvider,
            soundPlayer: TestPomodoroSoundPlayer(),
            notificationPoster: TestPomodoroNotificationPoster(),
            workspaceNotificationCenter: workspaceNotificationCenter,
            nowProvider: { clock.now },
            sleepHandler: { _ in
                try await Task.sleep(for: .seconds(3600))
            },
            persistenceDelay: .zero
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

    static func derivedMinutesReflectSecondOverrides() throws {
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "overrides"),
            clock: TestPomodoroClock(now: Date(timeIntervalSince1970: 2_000)),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 95, breakSeconds: 125)

        try expectEqual(vm.focusMinutes, 2)
        try expectEqual(vm.breakMinutes, 2)
    }

    static func manualPauseThenSkipDoesNotAutoResume() throws {
        let clock = TestPomodoroClock(now: Date(timeIntervalSince1970: 3_000))
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "manual-pause"),
            clock: clock,
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { vm.shutdown() }

        vm.autoStartBreaks = true
        vm.updateCurrentDurations(focusSeconds: 5, breakSeconds: 3)
        vm.start()
        vm.pause()
        vm.skipPhase()

        try expectEqual(vm.phase, .shortBreak)
        try expect(!vm.isRunning, "skip after a manual pause must not auto-resume")
    }

    static func cycleIndicatorsStayConsistentAcrossEdges() async throws {
        let clock = TestPomodoroClock(now: Date(timeIntervalSince1970: 4_000))
        let workspaceNotificationCenter = NotificationCenter()
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "cycle-indicators"),
            clock: clock,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 5, breakSeconds: 3)
        vm.updateSessionsBeforeLongBreak(count: 2)

        try expectEqual(vm.currentFocusSessionIndex, 1)
        try expectEqual(vm.completedSessionsInCycle, 0)

        vm.start()
        clock.now = clock.now.addingTimeInterval(6)
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        try expectEqual(vm.phase, .shortBreak)
        try expectEqual(vm.currentFocusSessionIndex, 1)
        try expectEqual(vm.completedSessionsInCycle, 1)

        clock.now = clock.now.addingTimeInterval(4)
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        try expectEqual(vm.phase, .focus)
        try expectEqual(vm.currentFocusSessionIndex, 2)
        try expectEqual(vm.completedSessionsInCycle, 1)

        clock.now = clock.now.addingTimeInterval(6)
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        try expectEqual(vm.phase, .longBreak)
        try expectEqual(vm.currentFocusSessionIndex, 2)
        try expectEqual(vm.completedSessionsInCycle, 2)

        vm.reset()
        try expectEqual(vm.currentFocusSessionIndex, 1)
        try expectEqual(vm.completedSessionsInCycle, 0)

        vm.updateSessionsBeforeLongBreak(count: 3)
        try expectEqual(vm.currentFocusSessionIndex, 1)
        try expectEqual(vm.completedSessionsInCycle, 0)
    }

    static func runningRestoreKeepsActiveTimer() throws {
        let baseTime = Date(timeIntervalSince1970: 6_000)
        let userDefaults = makeIsolatedUserDefaults(label: "running-restore")

        do {
            let liveClock = TestPomodoroClock(now: baseTime)
            let originalVM = makeViewModel(
                userDefaults: userDefaults,
                clock: liveClock,
                workspaceNotificationCenter: NotificationCenter()
            )
            originalVM.updateCurrentDurations(focusSeconds: 5, breakSeconds: 3)
            originalVM.start()
            originalVM.shutdown()
        }

        let restoredClock = TestPomodoroClock(now: baseTime.addingTimeInterval(2))
        let restoredVM = makeViewModel(
            userDefaults: userDefaults,
            clock: restoredClock,
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { restoredVM.shutdown() }

        try expect(restoredVM.isRunning)
        try expectEqual(restoredVM.phase, .focus)
        try expectEqual(restoredVM.remainingSeconds(at: restoredClock.now), 3)
    }

    static func pausedRestoreKeepsSessionPaused() throws {
        let baseTime = Date(timeIntervalSince1970: 7_000)
        let userDefaults = makeIsolatedUserDefaults(label: "paused-restore")
        let liveClock = TestPomodoroClock(now: baseTime)

        do {
            let originalVM = makeViewModel(
                userDefaults: userDefaults,
                clock: liveClock,
                workspaceNotificationCenter: NotificationCenter()
            )
            originalVM.updateCurrentDurations(focusSeconds: 5, breakSeconds: 3)
            originalVM.start()
            liveClock.now = baseTime.addingTimeInterval(2)
            originalVM.pause()
            originalVM.shutdown()
        }

        let restoredClock = TestPomodoroClock(now: baseTime.addingTimeInterval(20))
        let restoredVM = makeViewModel(
            userDefaults: userDefaults,
            clock: restoredClock,
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { restoredVM.shutdown() }

        try expect(!restoredVM.isRunning)
        try expect(restoredVM.hasActiveSession)
        try expectEqual(restoredVM.phase, .focus)
        try expectEqual(restoredVM.remainingSeconds, 3)
    }

    static func selectPresetClearsDurationOverrides() throws {
        let vm = makeViewModel(
            userDefaults: makeIsolatedUserDefaults(label: "preset-reset"),
            clock: TestPomodoroClock(now: Date(timeIntervalSince1970: 8_000)),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { vm.shutdown() }

        vm.updateCurrentDurations(focusSeconds: 95, breakSeconds: 125)
        vm.updateLongBreakDuration(seconds: 99)
        vm.selectPreset(.sprint)

        try expectEqual(vm.focusDurationOverrideSeconds, nil)
        try expectEqual(vm.breakDurationOverrideSeconds, nil)
        try expectEqual(vm.longBreakDurationOverrideSeconds, nil)
        try expectEqual(vm.focusDurationSeconds, PomodoroPreset.sprint.focusMinutes * 60)
        try expectEqual(vm.breakDurationSeconds, PomodoroPreset.sprint.breakMinutes * 60)
    }

    static func durationParserSupportsMinuteScaleClockContext() throws {
        try expectEqual(DurationParser.parse("1:30"), 90)
        try expectEqual(
            DurationParser.parse("1:30", colonContext: .minutesScale),
            5_400
        )
    }
}
