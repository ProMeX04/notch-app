import AppKit
import SwiftUI
import Combine

package struct FocusTask: Identifiable, Codable, Equatable {
    package let id: UUID
    package var title: String
    package var isCompleted: Bool
    package var completedSessions: Int
    package var createdAt: Date

    package init(id: UUID = UUID(), title: String, isCompleted: Bool = false, completedSessions: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedSessions = completedSessions
        self.createdAt = createdAt
    }
}

package enum PomodoroPhase: String {
    case focus = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    package var symbolName: String {
        switch self {
        case .focus:
            return "timer"
        case .shortBreak:
            return "cup.and.saucer.fill"
        case .longBreak:
            return "figure.walk"
        }
    }

    package var accentColor: NSColor {
        switch self {
        case .focus:
            // Brighter, lighter red (more towards salmon/neon)
            return NSColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 1)
        case .shortBreak:
            // Already good according to user
            return NSColor(red: 60/255, green: 215/255, blue: 105/255, alpha: 1)
        case .longBreak:
            // Brighter blue (more towards sky blue/cyan)
            return NSColor(red: 110/255, green: 190/255, blue: 255/255, alpha: 1)
        }
    }

    package var accentSwiftUIColor: Color {
        Color(nsColor: accentColor)
    }
}

private struct PomodoroRuntimeState: Codable {
    var phaseRawValue: String
    var remainingSeconds: Int
    var isRunning: Bool
    var hasActiveSession: Bool
    var phaseEndDate: Date?
    var completedFocusSessions: Int
    var recordedFocusSecondsForCurrentPhase: Int
    var wasManuallyPaused: Bool
}

@MainActor
package final class PomodoroViewModel: ObservableObject {
    @Published package private(set) var phase: PomodoroPhase = .focus {
        didSet {
            refreshPhaseReminder()
        }
    }
    @Published package private(set) var remainingSeconds: Int
    @Published package private(set) var isRunning = false
    @Published package private(set) var hasActiveSession = false
    @Published package var autoStartBreaks: Bool { didSet { persistSettings() } }
    @Published package var autoStartPomodoros: Bool { didSet { persistSettings() } }
    @Published package var notificationsEnabled: Bool { didSet { persistSettings() } }
    @Published package var showMenuBarClockDuringFocus: Bool { didSet { persistSettings() } }
    @Published package var tasks: [FocusTask] = [] { didSet { persistTasks() } }
    @Published package var selectedTaskId: UUID? = nil { didSet { persistTasks() } }
    
    package var currentTask: String {
        tasks.first(where: { $0.id == selectedTaskId })?.title ?? ""
    }
    @Published package private(set) var focusDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published package private(set) var breakDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published package private(set) var longBreakDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published package private(set) var sessionsBeforeLongBreakOverride: Int? { didSet { persistSettings() } }
    /// Matches `MotivationalQuotes` for the current phase — also used for system notifications when a phase begins (timer or skip).
    @Published package private(set) var phaseReminder: MotivationalQuote = MotivationalQuote(text: "", author: "")

    private var phaseCompletionTask: Task<Void, Never>?
    private var phaseEndDate: Date?
    private var scheduledPhaseTaskID = UUID()
    private var isHandlingPhaseCompletion = false
    /// Avoids wiping persisted `selectedTaskId` while assigning `tasks` then `selectedTaskId` during `loadTasks()`.
    private var suppressTaskPersistence = false
    private let userDefaults: UserDefaults
    private let learningStatsRecorder: LearningStatsRecording
    private let appLanguageProvider: AppLanguageProvider
    private let soundPlayer: PomodoroSoundPlaying
    private let notificationPoster: PomodoroNotificationPosting
    private let workspaceNotificationCenter: NotificationCenter
    private let nowProvider: () -> Date
    private let sleepHandler: @Sendable (TimeInterval) async throws -> Void
    private let persistenceDelay: Duration
    private var sleepWakeCancellables = Set<AnyCancellable>()
    private var providerCancellables = Set<AnyCancellable>()
    private var settingsPersistenceTask: Task<Void, Never>?
    private var runtimePersistenceTask: Task<Void, Never>?
    private var tasksPersistenceTask: Task<Void, Never>?
    @Published package private(set) var completedFocusSessions = 0
    private var recordedFocusSecondsForCurrentPhase = 0
    private var wasManuallyPaused = false

    package init(
        userDefaults: UserDefaults,
        learningStatsRecorder: LearningStatsRecording,
        appLanguageProvider: AppLanguageProvider,
        soundPlayer: PomodoroSoundPlaying = NoopPomodoroSoundPlayer(),
        notificationPoster: PomodoroNotificationPosting = NoopPomodoroNotificationPoster(),
        workspaceNotificationCenter: NotificationCenter,
        nowProvider: @escaping () -> Date,
        sleepHandler: @escaping @Sendable (TimeInterval) async throws -> Void,
        persistenceDelay: Duration = .milliseconds(250)
    ) {
        self.userDefaults = userDefaults
        self.learningStatsRecorder = learningStatsRecorder
        self.appLanguageProvider = appLanguageProvider
        self.soundPlayer = soundPlayer
        self.notificationPoster = notificationPoster
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.nowProvider = nowProvider
        self.sleepHandler = sleepHandler
        self.persistenceDelay = persistenceDelay

        let focusDurationOverrideSeconds = Self.optionalInt(
            forKey: Self.focusDurationOverrideSecondsKey,
            from: userDefaults,
            minimum: 1
        )
        let breakDurationOverrideSeconds = Self.optionalInt(
            forKey: Self.breakDurationOverrideSecondsKey,
            from: userDefaults,
            minimum: 1
        )
        let longBreakDurationOverrideSeconds = Self.optionalInt(
            forKey: Self.longBreakDurationOverrideSecondsKey,
            from: userDefaults,
            minimum: 1
        )
        let sessionsBeforeLongBreakOverride = Self.optionalInt(
            forKey: Self.sessionsBeforeLongBreakOverrideKey,
            from: userDefaults,
            minimum: 1
        )

        self.autoStartBreaks = userDefaults.bool(forKey: Self.autoStartBreaksKey)
        self.autoStartPomodoros = userDefaults.bool(forKey: Self.autoStartPomodorosKey)
        if userDefaults.object(forKey: Self.notificationsEnabledKey) != nil {
            self.notificationsEnabled = userDefaults.bool(forKey: Self.notificationsEnabledKey)
        } else {
            self.notificationsEnabled = true // Default to true if not set
        }
        if userDefaults.object(forKey: Self.showMenuBarClockDuringFocusKey) != nil {
            self.showMenuBarClockDuringFocus = userDefaults.bool(forKey: Self.showMenuBarClockDuringFocusKey)
        } else {
            self.showMenuBarClockDuringFocus = true
        }
        self.focusDurationOverrideSeconds = focusDurationOverrideSeconds
        self.breakDurationOverrideSeconds = breakDurationOverrideSeconds
        self.longBreakDurationOverrideSeconds = longBreakDurationOverrideSeconds
        self.sessionsBeforeLongBreakOverride = sessionsBeforeLongBreakOverride

        remainingSeconds = focusDurationOverrideSeconds ?? Self.defaultFocusDurationSeconds
        loadTasks()
        restoreRuntimeStateIfAvailable()
        configureSleepWakeObservers()
        configureLanguageObserver()
        // `phase` may stay `.focus` after restore (no `didSet` fire) — ensure a reminder exists.
        refreshPhaseReminder()
    }

    package var languageProvider: AppLanguageProvider {
        appLanguageProvider
    }

    package var focusMinutes: Int {
        max(Int((Double(focusDurationSeconds) / 60).rounded()), 1)
    }

    package var breakMinutes: Int {
        max(Int((Double(breakDurationSeconds) / 60).rounded()), 1)
    }

    package var focusDurationSeconds: Int {
        focusDurationOverrideSeconds ?? Self.defaultFocusDurationSeconds
    }

    package var breakDurationSeconds: Int {
        breakDurationOverrideSeconds ?? Self.defaultBreakDurationSeconds
    }

    package var longBreakDurationSeconds: Int {
        longBreakDurationOverrideSeconds ?? Self.defaultLongBreakDurationSeconds
    }

    package var actionTitle: String {
        if isRunning {
            return "Pause"
        }

        return hasActiveSession ? "Resume" : "Start"
    }

    package var statusLine: String {
        if isRunning {
            return phase == .focus ? "Stay locked in" : "Take a quick breather"
        }

        if hasActiveSession {
            return "Paused with \(remainingText()) remaining"
        }

        let durationText: String
        switch phase {
        case .focus:
            durationText = DurationParser.displayString(for: focusDurationSeconds)
        case .shortBreak:
            durationText = DurationParser.displayString(for: breakDurationSeconds)
        case .longBreak:
            durationText = DurationParser.displayString(for: longBreakDurationSeconds)
        }

        return "Ready for your \(durationText) \(phase.rawValue) session"
    }

    package var nextPhaseLine: String {
        let nextPhase = nextPhase(after: phase)
        return "Up next: \(nextPhase.rawValue) \(DurationParser.displayString(for: duration(for: nextPhase)))"
    }

    package var sessionsBeforeLongBreak: Int {
        sessionsBeforeLongBreakOverride ?? Self.defaultSessionsBeforeLongBreak
    }

    /// The round indicator is phase-aware:
    /// - focus shows the currently active session in the cycle
    /// - breaks show the session that just completed
    /// - long break pins to the last session in the cycle
    package var currentFocusSessionIndex: Int {
        if phase == .longBreak { return sessionsBeforeLongBreak }
        let index = (completedFocusSessions % sessionsBeforeLongBreak)
        if phase == .focus {
            return index + 1
        } else {
            // Break phase: if index is 0 after completing a multiple of cycles,
            // it means we finished the last session of the previous cycle.
            return index == 0 ? sessionsBeforeLongBreak : index
        }
    }

    /// The session dots show completed focus sessions within the current cycle.
    /// During a break right after finishing the cycle, the dots stay filled.
    package var completedSessionsInCycle: Int {
        if phase == .longBreak { return sessionsBeforeLongBreak }
        let index = completedFocusSessions % sessionsBeforeLongBreak
        // If we finished a session (it's a break phase) and it happened to be a multiple,
        // return the full count. Otherwise (including focus phase), return the remainder.
        if phase != .focus && index == 0 && completedFocusSessions > 0 {
            return sessionsBeforeLongBreak
        }
        return index
    }

    package func remainingSeconds(at date: Date = .now) -> Int {
        guard isRunning, let phaseEndDate else {
            return remainingSeconds
        }

        return max(Int(ceil(phaseEndDate.timeIntervalSince(date))), 0)
    }

    package func remainingText(at date: Date = .now) -> String {
        let remainingSeconds = remainingSeconds(at: date)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    package func toggleRunning() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    package func start() {
        start(force: false)
    }

    private func start(force: Bool) {
        guard force || !isRunning else { return }
        hasActiveSession = true
        isRunning = true
        wasManuallyPaused = false
        phaseEndDate = nowProvider().addingTimeInterval(TimeInterval(remainingSeconds))
        startPhaseCompletionTask()
        persistRuntimeState()
    }

    package func pause(manual: Bool = true) {
        guard isRunning else { return }

        let now = nowProvider()
        recordCurrentFocusProgressIfNeeded(referenceDate: now)
        remainingSeconds = remainingSeconds(at: now)
        isRunning = false
        if manual {
            wasManuallyPaused = true
        }
        phaseEndDate = nil
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        scheduledPhaseTaskID = UUID()
        persistRuntimeState()
    }

    package func reset() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus)
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        persistRuntimeState()
        refreshPhaseReminder()
    }

    package func skipPhase() {
        let shouldContinueRunning = isRunning
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        advancePhase(continueRunning: shouldContinueRunning, postTransitionNotification: true)
        persistRuntimeState()
    }

    package func setPhase(_ targetPhase: PomodoroPhase) {
        guard phase != targetPhase else { return }
        let shouldContinueRunning = isRunning
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        
        phase = targetPhase
        remainingSeconds = duration(for: phase)
        hasActiveSession = true
        recordedFocusSecondsForCurrentPhase = 0
        if shouldContinueRunning {
            restartPhase()
        } else {
            isRunning = false
            persistRuntimeState()
        }
    }

    package func updateCurrentDurations(focusMinutes: Int, breakMinutes: Int) {
        let clampedFocusMinutes = max(5, min(focusMinutes, 180))
        let clampedBreakMinutes = max(1, min(breakMinutes, 60))
        updateCurrentDurations(
            focusSeconds: clampedFocusMinutes * 60,
            breakSeconds: clampedBreakMinutes * 60
        )
    }

    package func updateCurrentDurations(focusSeconds: Int, breakSeconds: Int) {
        let clampedFocusSeconds = max(1, min(focusSeconds, 180 * 60))
        let clampedBreakSeconds = max(1, min(breakSeconds, 60 * 60))

        guard focusDurationSeconds != clampedFocusSeconds || breakDurationSeconds != clampedBreakSeconds else {
            return
        }

        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        focusDurationOverrideSeconds = clampedFocusSeconds
        breakDurationOverrideSeconds = clampedBreakSeconds
        remainingSeconds = clampedFocusSeconds
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        persistRuntimeState()
    }

    package func updateLongBreakDuration(minutes: Int) {
        let clamped = max(1, min(minutes, 60))
        let newSeconds = clamped * 60
        guard longBreakDurationSeconds != newSeconds else { return }
        longBreakDurationOverrideSeconds = newSeconds
        // If we're idling on the long-break phase, reflect the new duration immediately
        if phase == .longBreak && !hasActiveSession {
            remainingSeconds = newSeconds
        }
        persistRuntimeState()
    }

    package func updateLongBreakDuration(seconds: Int) {
        let clamped = max(1, min(seconds, 60 * 60))
        guard longBreakDurationSeconds != clamped else { return }
        longBreakDurationOverrideSeconds = clamped
        if phase == .longBreak && !hasActiveSession {
            remainingSeconds = clamped
        }
        persistRuntimeState()
    }

    package func updateSessionsBeforeLongBreak(count: Int) {
        let clamped = max(1, min(count, 12))
        guard sessionsBeforeLongBreakOverride != clamped else { return }
        sessionsBeforeLongBreakOverride = clamped
        persistRuntimeState()
    }

    package func shutdown() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        flushPendingPersistence()
        persistSettingsImmediately()
        persistRuntimeStateImmediately()
        persistTasksImmediately()
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        scheduledPhaseTaskID = UUID()
        sleepWakeCancellables.removeAll()
        providerCancellables.removeAll()
    }

    private func refreshPhaseReminder() {
        let lang = appLanguageProvider.currentLanguage
        phaseReminder = MotivationalQuotes.getRandom(for: phase, lang: lang)
    }

    private func postPhaseStartedNotification() {
        guard notificationsEnabled else { return }
        notificationPoster.postPhaseStarted(
            phase: phase,
            reminder: phaseReminder,
            language: appLanguageProvider.currentLanguage
        )
    }

    private func advancePhase(continueRunning: Bool, postTransitionNotification: Bool = false) {
        let hadActiveSession = hasActiveSession
        if phase == .focus {
            recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
            completedFocusSessions += 1
            
            // Increment session count for the selected task
            if let selectedId = selectedTaskId,
               let index = tasks.firstIndex(where: { $0.id == selectedId }) {
                tasks[index].completedSessions += 1
            }
            
            phase = nextBreakPhase
        } else {
            phase = .focus
        }

        remainingSeconds = duration(for: phase)
        phaseEndDate = nil
        hasActiveSession = continueRunning || hadActiveSession
        recordedFocusSecondsForCurrentPhase = 0

        let shouldAutoStart: Bool
        if phase == .focus {
            shouldAutoStart = autoStartPomodoros
        } else {
            shouldAutoStart = autoStartBreaks
        }

        let shouldContinueIntoNextPhase = continueRunning
            || (!continueRunning && hadActiveSession && shouldAutoStart && !wasManuallyPaused)

        if shouldContinueIntoNextPhase {
            restartPhase()
        } else {
            isRunning = false
            persistRuntimeState()
        }

        if postTransitionNotification {
            postPhaseStartedNotification()
        }
    }

    private func configureSleepWakeObservers() {
        workspaceNotificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemWillSleep()
            }
            .store(in: &sleepWakeCancellables)

        workspaceNotificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemDidWake()
            }
            .store(in: &sleepWakeCancellables)
    }

    private func configureLanguageObserver() {
        appLanguageProvider.$currentLanguage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPhaseReminder()
            }
            .store(in: &providerCancellables)
    }

    private func handleSystemWillSleep() {
        guard isRunning else { return }
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
    }

    private func handleSystemDidWake() {
        syncRunningPhaseWithCurrentTime(
            now: nowProvider(),
            allowCatchUpTransitions: 1,
            playCompletionSound: true,
            postTransitionNotification: true,
            pauseOnOverflow: false
        )
    }

    private func startPhaseCompletionTask() {
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil

        guard isRunning, let phaseEndDate else { return }

        let duration = max(phaseEndDate.timeIntervalSince(nowProvider()), 0)
        let taskID = UUID()
        scheduledPhaseTaskID = taskID

        phaseCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if duration <= 0 {
                self.handlePhaseCompletionIfNeeded(
                    expectedPhaseEndDate: phaseEndDate,
                    expectedTaskID: taskID,
                    playCompletionSound: true,
                    postTransitionNotification: true
                )
                return
            }

            do {
                try await self.sleepHandler(duration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self.handlePhaseCompletionIfNeeded(
                expectedPhaseEndDate: phaseEndDate,
                expectedTaskID: taskID,
                playCompletionSound: true,
                postTransitionNotification: true
            )
        }
    }

    private func handlePhaseCompletionIfNeeded(
        expectedPhaseEndDate: Date,
        expectedTaskID: UUID?,
        playCompletionSound: Bool,
        postTransitionNotification: Bool
    ) {
        guard isRunning, let activePhaseEndDate = phaseEndDate else { return }
        if let expectedTaskID, scheduledPhaseTaskID != expectedTaskID { return }
        guard activePhaseEndDate == expectedPhaseEndDate else { return }
        guard activePhaseEndDate <= nowProvider() else {
            remainingSeconds = remainingSeconds(at: nowProvider())
            startPhaseCompletionTask()
            persistRuntimeState()
            return
        }
        guard !isHandlingPhaseCompletion else { return }

        isHandlingPhaseCompletion = true
        defer { isHandlingPhaseCompletion = false }

        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        scheduledPhaseTaskID = UUID()
        remainingSeconds = 0
        phaseEndDate = nil

        if playCompletionSound {
            switch phase {
            case .focus:
                soundPlayer.playFocusComplete()
            case .shortBreak, .longBreak:
                soundPlayer.playBreakComplete()
            }
        }

        advancePhase(continueRunning: true, postTransitionNotification: postTransitionNotification)
    }

    private func duration(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus:
            return focusDurationSeconds
        case .shortBreak:
            return breakDurationSeconds
        case .longBreak:
            return longBreakDurationSeconds
        }
    }

    private var nextBreakPhase: PomodoroPhase {
        completedFocusSessions.isMultiple(of: sessionsBeforeLongBreak) ? .longBreak : .shortBreak
    }

    private func nextPhase(after phase: PomodoroPhase) -> PomodoroPhase {
        switch phase {
        case .focus:
            let projectedCompletedSessions = completedFocusSessions + 1
            return projectedCompletedSessions.isMultiple(of: sessionsBeforeLongBreak) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    private func recordCurrentFocusProgressIfNeeded(referenceDate: Date) {
        guard phase == .focus else { return }

        let elapsedFocusSeconds = max(duration(for: .focus) - remainingSeconds(at: referenceDate), 0)
        let delta = elapsedFocusSeconds - recordedFocusSecondsForCurrentPhase
        guard delta > 0 else { return }

        learningStatsRecorder.record(seconds: delta, source: .pomodoro)
        recordedFocusSecondsForCurrentPhase += delta
    }

    private func persistSettings() {
        schedulePersistence(
            task: &settingsPersistenceTask,
            operation: { [weak self] in
                self?.persistSettingsImmediately()
            }
        )
    }

    private func persistSettingsImmediately() {
        userDefaults.set(autoStartBreaks, forKey: Self.autoStartBreaksKey)
        userDefaults.set(autoStartPomodoros, forKey: Self.autoStartPomodorosKey)
        userDefaults.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
        userDefaults.set(showMenuBarClockDuringFocus, forKey: Self.showMenuBarClockDuringFocusKey)
        persistOptionalInt(focusDurationOverrideSeconds, forKey: Self.focusDurationOverrideSecondsKey)
        persistOptionalInt(breakDurationOverrideSeconds, forKey: Self.breakDurationOverrideSecondsKey)
        persistOptionalInt(longBreakDurationOverrideSeconds, forKey: Self.longBreakDurationOverrideSecondsKey)
        persistOptionalInt(sessionsBeforeLongBreakOverride, forKey: Self.sessionsBeforeLongBreakOverrideKey)
    }

    private func persistRuntimeState() {
        schedulePersistence(
            task: &runtimePersistenceTask,
            operation: { [weak self] in
                self?.persistRuntimeStateImmediately()
            }
        )
    }

    private func persistRuntimeStateImmediately() {
        let snapshot = PomodoroRuntimeState(
            phaseRawValue: phase.rawValue,
            remainingSeconds: remainingSeconds(at: nowProvider()),
            isRunning: isRunning,
            hasActiveSession: hasActiveSession,
            phaseEndDate: phaseEndDate,
            completedFocusSessions: completedFocusSessions,
            recordedFocusSecondsForCurrentPhase: recordedFocusSecondsForCurrentPhase,
            wasManuallyPaused: wasManuallyPaused
        )

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(encoded, forKey: Self.runtimeStateDefaultsKey)
    }

    private func restoreRuntimeStateIfAvailable(now: Date? = nil) {
        let now = now ?? nowProvider()
        guard let data = userDefaults.data(forKey: Self.runtimeStateDefaultsKey),
              let snapshot = try? JSONDecoder().decode(PomodoroRuntimeState.self, from: data),
              let restoredPhase = PomodoroPhase(rawValue: snapshot.phaseRawValue) else {
            return
        }

        phase = restoredPhase
        completedFocusSessions = max(snapshot.completedFocusSessions, 0)
        recordedFocusSecondsForCurrentPhase = max(snapshot.recordedFocusSecondsForCurrentPhase, 0)
        wasManuallyPaused = snapshot.wasManuallyPaused

        if snapshot.isRunning, let savedPhaseEndDate = snapshot.phaseEndDate {
            restoreRunningStateFromSnapshot(
                from: snapshot,
                phase: restoredPhase,
                phaseEndDate: savedPhaseEndDate,
                now: now
            )
            return
        }

        isRunning = false
        phaseEndDate = nil
        hasActiveSession = snapshot.hasActiveSession
        remainingSeconds = clampedRemainingSeconds(
            snapshot.remainingSeconds,
            for: restoredPhase,
            activeSession: snapshot.hasActiveSession
        )
        persistRuntimeState()
    }

    private func restoreRunningStateFromSnapshot(
        from snapshot: PomodoroRuntimeState,
        phase: PomodoroPhase,
        phaseEndDate: Date,
        now: Date
    ) {
        var restoredPhase = phase
        var restoredCompletedFocusSessions = max(snapshot.completedFocusSessions, 0)
        var restoredPhaseEndDate = phaseEndDate
        var transitions = 0
        var didAdvance = false

        while restoredPhaseEndDate <= now {
            guard transitions < Self.maximumRestoreCatchUpTransitions else {
                self.phase = restoredPhase
                self.completedFocusSessions = restoredCompletedFocusSessions
                self.recordedFocusSecondsForCurrentPhase = 0
                applyRestoreOverflowState()
                return
            }

            let nextState = restoredTransition(
                after: restoredPhase,
                completedFocusSessions: restoredCompletedFocusSessions
            )
            restoredPhase = nextState.phase
            restoredCompletedFocusSessions = nextState.completedFocusSessions
            restoredPhaseEndDate = restoredPhaseEndDate.addingTimeInterval(
                TimeInterval(duration(for: restoredPhase))
            )
            transitions += 1
            didAdvance = true
        }

        self.phase = restoredPhase
        self.completedFocusSessions = restoredCompletedFocusSessions
        self.recordedFocusSecondsForCurrentPhase = 0
        self.hasActiveSession = true
        self.isRunning = true
        self.wasManuallyPaused = false
        self.phaseEndDate = restoredPhaseEndDate
        self.remainingSeconds = clampedRemainingSeconds(
            max(Int(ceil(restoredPhaseEndDate.timeIntervalSince(now))), 0),
            for: restoredPhase,
            activeSession: true
        )
        startPhaseCompletionTask()
        persistRuntimeState()

        if didAdvance {
            postPhaseStartedNotification()
        }
    }

    @discardableResult
    private func syncRunningPhaseWithCurrentTime(
        now: Date,
        allowCatchUpTransitions: Int,
        playCompletionSound: Bool,
        postTransitionNotification: Bool,
        pauseOnOverflow: Bool
    ) -> Bool {
        guard isRunning, let activePhaseEndDate = phaseEndDate else { return false }

        if activePhaseEndDate > now {
            remainingSeconds = clampedRemainingSeconds(
                max(Int(ceil(activePhaseEndDate.timeIntervalSince(now))), 0),
                for: phase,
                activeSession: true
            )
            startPhaseCompletionTask()
            persistRuntimeState()
            return false
        }

        var transitions = 0
        var didAdvance = false

        while isRunning, let currentPhaseEndDate = phaseEndDate, currentPhaseEndDate <= now {
            if transitions >= allowCatchUpTransitions {
                if pauseOnOverflow {
                    applyRestoreOverflowState()
                    postPhaseStartedNotification()
                } else {
                    handlePhaseCompletionIfNeeded(
                        expectedPhaseEndDate: currentPhaseEndDate,
                        expectedTaskID: nil,
                        playCompletionSound: playCompletionSound,
                        postTransitionNotification: postTransitionNotification
                    )
                }
                return true
            }

            handlePhaseCompletionIfNeeded(
                expectedPhaseEndDate: currentPhaseEndDate,
                expectedTaskID: nil,
                playCompletionSound: playCompletionSound && transitions == 0,
                postTransitionNotification: false
            )
            transitions += 1
            didAdvance = true
        }

        if didAdvance {
            postPhaseStartedNotification()
        }

        return didAdvance
    }

    private func applyRestoreOverflowState() {
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        remainingSeconds = duration(for: phase)
        persistRuntimeState()
    }

    private func restartPhase() {
        start(force: true)
    }

    private func clampedRemainingSeconds(_ seconds: Int, for phase: PomodoroPhase, activeSession: Bool) -> Int {
        let phaseDuration = duration(for: phase)
        if activeSession {
            return max(0, min(seconds, phaseDuration))
        }
        return phaseDuration
    }

    private func restoredTransition(
        after phase: PomodoroPhase,
        completedFocusSessions: Int
    ) -> (phase: PomodoroPhase, completedFocusSessions: Int) {
        switch phase {
        case .focus:
            let newCompletedFocusSessions = completedFocusSessions + 1
            let nextPhase: PomodoroPhase = newCompletedFocusSessions.isMultiple(of: sessionsBeforeLongBreak)
                ? .longBreak
                : .shortBreak
            return (nextPhase, newCompletedFocusSessions)
        case .shortBreak, .longBreak:
            return (.focus, completedFocusSessions)
        }
    }

    private static let maximumRestoreCatchUpTransitions = 3

    private func persistOptionalInt(_ value: Int?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func optionalInt(forKey key: String, from userDefaults: UserDefaults, minimum: Int) -> Int? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        let value = userDefaults.integer(forKey: key)
        return value >= minimum ? value : nil
    }

    private static let autoStartBreaksKey = "NotchPomodoroAutoStartBreaks"
    private static let autoStartPomodorosKey = "NotchPomodoroAutoStartPomodoros"
    private static let notificationsEnabledKey = "NotchPomodoroNotificationsEnabled"
    private static let showMenuBarClockDuringFocusKey = "NotchPomodoroShowMenuBarClockDuringFocus"
    private static let focusDurationOverrideSecondsKey = "NotchPomodoroFocusDurationOverrideSeconds"
    private static let breakDurationOverrideSecondsKey = "NotchPomodoroBreakDurationOverrideSeconds"
    private static let longBreakDurationOverrideSecondsKey = "NotchPomodoroLongBreakDurationOverrideSeconds"
    private static let sessionsBeforeLongBreakOverrideKey = "NotchPomodoroSessionsBeforeLongBreakOverride"
    private static let runtimeStateDefaultsKey = "NotchPomodoroRuntimeState"
    private static let tasksKey = "NotchPomodoroTasks"
    private static let selectedTaskIdKey = "NotchPomodoroSelectedTaskId"
    private static let defaultFocusDurationSeconds = 25 * 60
    private static let defaultBreakDurationSeconds = 5 * 60
    private static let defaultLongBreakDurationSeconds = 15 * 60
    private static let defaultSessionsBeforeLongBreak = 4

    private func persistTasks() {
        guard !suppressTaskPersistence else { return }
        schedulePersistence(
            task: &tasksPersistenceTask,
            operation: { [weak self] in
                self?.persistTasksImmediately()
            }
        )
    }

    private func persistTasksImmediately() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            userDefaults.set(encoded, forKey: Self.tasksKey)
        }
        if let id = selectedTaskId {
            userDefaults.set(id.uuidString, forKey: Self.selectedTaskIdKey)
        } else {
            userDefaults.removeObject(forKey: Self.selectedTaskIdKey)
        }
    }

    private func flushPendingPersistence() {
        settingsPersistenceTask?.cancel()
        runtimePersistenceTask?.cancel()
        tasksPersistenceTask?.cancel()
        settingsPersistenceTask = nil
        runtimePersistenceTask = nil
        tasksPersistenceTask = nil
    }

    private func schedulePersistence(
        task: inout Task<Void, Never>?,
        operation: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        guard persistenceDelay > .zero else {
            operation()
            return
        }

        let delay = persistenceDelay
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            operation()
        }
    }

    private func loadTasks() {
        suppressTaskPersistence = true
        defer {
            suppressTaskPersistence = false
            persistTasks()
        }

        let loadedTasks: [FocusTask]
        if let data = userDefaults.data(forKey: Self.tasksKey),
           let decoded = try? JSONDecoder().decode([FocusTask].self, from: data) {
            loadedTasks = decoded
        } else {
            loadedTasks = []
        }

        var selection: UUID?
        if let idString = userDefaults.string(forKey: Self.selectedTaskIdKey),
           let id = UUID(uuidString: idString) {
            selection = id
        }

        tasks = loadedTasks

        if let id = selection, loadedTasks.contains(where: { $0.id == id }) {
            selectedTaskId = id
        } else {
            selectedTaskId = nil
        }
    }
}
