import AppKit
import SwiftUI
import Combine

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedSessions: Int
    var createdAt: Date

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, completedSessions: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedSessions = completedSessions
        self.createdAt = createdAt
    }
}

enum PomodoroPhase: String {
    case focus = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    var symbolName: String {
        switch self {
        case .focus:
            return "timer"
        case .shortBreak:
            return "cup.and.saucer.fill"
        case .longBreak:
            return "figure.walk"
        }
    }

    var accentColor: NSColor {
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

    var accentSwiftUIColor: Color {
        Color(nsColor: accentColor)
    }
}

enum PomodoroFocusMode: String, CaseIterable, Codable {
    case off = "Off"
    case zen = "Zen"
    case strict = "Strict"
}

struct PomodoroPreset: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var focusMinutes: Int
    var breakMinutes: Int
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int = 4
    var isCustom: Bool

    var chipTitle: String {
        "\(focusMinutes)/\(breakMinutes)"
    }

    static let sprint = PomodoroPreset(
        id: "sprint",
        title: "Sprint",
        focusMinutes: 15,
        breakMinutes: 3,
        longBreakMinutes: 10,
        isCustom: false
    )

    static let classic = PomodoroPreset(
        id: "classic",
        title: "Classic",
        focusMinutes: 25,
        breakMinutes: 5,
        longBreakMinutes: 15,
        isCustom: false
    )

    static let deep = PomodoroPreset(
        id: "deep",
        title: "Deep",
        focusMinutes: 50,
        breakMinutes: 10,
        longBreakMinutes: 30,
        isCustom: false
    )

    static let builtInPresets = [sprint, classic, deep]
    static let defaultCustomPresets = [
        PomodoroPreset(id: "custom-1", title: "Custom 1", focusMinutes: 20, breakMinutes: 5, longBreakMinutes: 15, isCustom: true),
        PomodoroPreset(id: "custom-2", title: "Custom 2", focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 20, isCustom: true),
        PomodoroPreset(id: "custom-3", title: "Custom 3", focusMinutes: 90, breakMinutes: 15, longBreakMinutes: 30, isCustom: true),
    ]
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
final class PomodoroViewModel: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .focus {
        didSet {
            refreshPhaseReminder()
        }
    }
    @Published private(set) var preset: PomodoroPreset
    @Published private(set) var customPresets: [PomodoroPreset]
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var hasActiveSession = false
    @Published var autoStartBreaks: Bool { didSet { persistSettings() } }
    @Published var autoStartPomodoros: Bool { didSet { persistSettings() } }
    @Published var tasks: [FocusTask] = [] { didSet { persistTasks() } }
    @Published var selectedTaskId: UUID? = nil { didSet { persistTasks() } }
    
    var currentTask: String {
        tasks.first(where: { $0.id == selectedTaskId })?.title ?? ""
    }
    @Published private(set) var focusDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published private(set) var breakDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published private(set) var longBreakDurationOverrideSeconds: Int? { didSet { persistSettings() } }
    @Published private(set) var sessionsBeforeLongBreakOverride: Int? { didSet { persistSettings() } }
    @Published private(set) var focusMode: PomodoroFocusMode { didSet { persistSettings() } }
    @Published private(set) var isFullscreenActive = false
    /// Matches `MotivationalQuotes` for the current phase — also used for system notifications when a phase begins (timer or skip).
    @Published private(set) var phaseReminder: MotivationalQuote = MotivationalQuote(text: "", author: "")

    private var phaseCompletionTask: Task<Void, Never>?
    private var phaseEndDate: Date?
    private var scheduledPhaseTaskID = UUID()
    private var isHandlingPhaseCompletion = false
    /// Avoids wiping persisted `selectedTaskId` while assigning `tasks` then `selectedTaskId` during `loadTasks()`.
    private var suppressTaskPersistence = false
    private let userDefaults: UserDefaults
    private let learningStatsRecorder: LearningStatsRecording
    private let appLanguageProvider: AppLanguageProvider
    private let workspaceNotificationCenter: NotificationCenter
    private let nowProvider: () -> Date
    private let sleepHandler: @Sendable (TimeInterval) async throws -> Void
    private let persistenceDelay: Duration
    private var sleepWakeCancellables = Set<AnyCancellable>()
    private var providerCancellables = Set<AnyCancellable>()
    private var settingsPersistenceTask: Task<Void, Never>?
    private var runtimePersistenceTask: Task<Void, Never>?
    private var tasksPersistenceTask: Task<Void, Never>?
    @Published private(set) var completedFocusSessions = 0
    private var recordedFocusSecondsForCurrentPhase = 0
    private var wasManuallyPaused = false

    convenience init(
        userDefaults: UserDefaults = .standard,
        learningStatsStore: LearningStatsStore
    ) {
        self.init(
            userDefaults: userDefaults,
            learningStatsRecorder: learningStatsStore,
            appLanguageProvider: AppLanguageProvider(userDefaults: userDefaults),
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            nowProvider: { .now },
            sleepHandler: { duration in
                try await Task.sleep(for: .seconds(duration))
            },
            persistenceDelay: .milliseconds(250)
        )
    }

    init(
        userDefaults: UserDefaults,
        learningStatsRecorder: LearningStatsRecording,
        appLanguageProvider: AppLanguageProvider,
        workspaceNotificationCenter: NotificationCenter,
        nowProvider: @escaping () -> Date,
        sleepHandler: @escaping @Sendable (TimeInterval) async throws -> Void,
        persistenceDelay: Duration = .milliseconds(250)
    ) {
        self.userDefaults = userDefaults
        self.learningStatsRecorder = learningStatsRecorder
        self.appLanguageProvider = appLanguageProvider
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
        self.focusDurationOverrideSeconds = focusDurationOverrideSeconds
        self.breakDurationOverrideSeconds = breakDurationOverrideSeconds
        self.longBreakDurationOverrideSeconds = longBreakDurationOverrideSeconds
        self.sessionsBeforeLongBreakOverride = sessionsBeforeLongBreakOverride

        let rawFocusMode = userDefaults.string(forKey: Self.focusModeKey) ?? ""
        self.focusMode = PomodoroFocusMode(rawValue: rawFocusMode) ?? .off

        let restoredCustomPresets = Self.loadCustomPresets(from: userDefaults)
        customPresets = restoredCustomPresets

        let selectedPresetID = userDefaults.string(forKey: Self.selectedPresetIDDefaultsKey)
        let resolvedPreset = Self.resolvePreset(
            matching: selectedPresetID,
            customPresets: restoredCustomPresets
        ) ?? .classic

        preset = resolvedPreset
        remainingSeconds = focusDurationOverrideSeconds ?? (resolvedPreset.focusMinutes * 60)
        loadTasks()
        restoreRuntimeStateIfAvailable()
        configureSleepWakeObservers()
        configureLanguageObserver()
        // `phase` may stay `.focus` after restore (no `didSet` fire) — ensure a reminder exists.
        refreshPhaseReminder()
    }

    var languageProvider: AppLanguageProvider {
        appLanguageProvider
    }

    var availablePresets: [PomodoroPreset] {
        PomodoroPreset.builtInPresets + customPresets
    }

    var focusMinutes: Int {
        max(Int((Double(focusDurationSeconds) / 60).rounded()), 1)
    }

    var breakMinutes: Int {
        max(Int((Double(breakDurationSeconds) / 60).rounded()), 1)
    }

    var focusDurationSeconds: Int {
        focusDurationOverrideSeconds ?? (preset.focusMinutes * 60)
    }

    var breakDurationSeconds: Int {
        breakDurationOverrideSeconds ?? (preset.breakMinutes * 60)
    }

    var longBreakDurationSeconds: Int {
        longBreakDurationOverrideSeconds ?? (preset.longBreakMinutes * 60)
    }

    var actionTitle: String {
        if isRunning {
            return "Pause"
        }

        return hasActiveSession ? "Resume" : "Start"
    }

    var statusLine: String {
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

    var nextPhaseLine: String {
        let nextPhase = nextPhase(after: phase)
        return "Up next: \(nextPhase.rawValue) \(DurationParser.displayString(for: duration(for: nextPhase, preset: preset)))"
    }

    var sessionsBeforeLongBreak: Int {
        sessionsBeforeLongBreakOverride ?? preset.sessionsBeforeLongBreak
    }

    /// The round indicator is phase-aware:
    /// - focus shows the currently active session in the cycle
    /// - breaks show the session that just completed
    /// - long break pins to the last session in the cycle
    var currentFocusSessionIndex: Int {
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
    var completedSessionsInCycle: Int {
        if phase == .longBreak { return sessionsBeforeLongBreak }
        let index = completedFocusSessions % sessionsBeforeLongBreak
        // If we finished a session (it's a break phase) and it happened to be a multiple,
        // return the full count. Otherwise (including focus phase), return the remainder.
        if phase != .focus && index == 0 && completedFocusSessions > 0 {
            return sessionsBeforeLongBreak
        }
        return index
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard isRunning, let phaseEndDate else {
            return remainingSeconds
        }

        return max(Int(ceil(phaseEndDate.timeIntervalSince(date))), 0)
    }

    func remainingText(at date: Date = .now) -> String {
        let remainingSeconds = remainingSeconds(at: date)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func toggleRunning() {
        if isRunning {
            pause()
        } else {
            start()
            SoundManager.playNotification()
        }
    }

    func start() {
        start(force: false)
    }

    private func start(force: Bool) {
        guard force || !isRunning else { return }
        hasActiveSession = true
        isRunning = true
        wasManuallyPaused = false
        evaluateFullscreenState()
        phaseEndDate = nowProvider().addingTimeInterval(TimeInterval(remainingSeconds))
        startPhaseCompletionTask()
        persistRuntimeState()
    }

    func pause(manual: Bool = true) {
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

    func reset() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        isFullscreenActive = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus, preset: preset)
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        persistRuntimeState()
        refreshPhaseReminder()
    }

    func skipPhase() {
        let shouldContinueRunning = isRunning
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        advancePhase(continueRunning: shouldContinueRunning, postTransitionNotification: true)
        persistRuntimeState()
    }

    func setPhase(_ targetPhase: PomodoroPhase) {
        guard phase != targetPhase else { return }
        let shouldContinueRunning = isRunning
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        
        phase = targetPhase
        remainingSeconds = duration(for: phase, preset: preset)
        hasActiveSession = true
        recordedFocusSecondsForCurrentPhase = 0
        if shouldContinueRunning {
            restartPhase()
        } else {
            isRunning = false
            persistRuntimeState()
        }
    }

    func selectPreset(_ preset: PomodoroPreset) {
        guard self.preset != preset else { return }

        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        self.preset = preset
        persistSelectedPresetID()
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        scheduledPhaseTaskID = UUID()
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus, preset: preset)
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        focusDurationOverrideSeconds = nil
        breakDurationOverrideSeconds = nil
        longBreakDurationOverrideSeconds = nil
        persistRuntimeState()
        refreshPhaseReminder()
    }

    func updateCurrentDurations(focusMinutes: Int, breakMinutes: Int) {
        let clampedFocusMinutes = max(5, min(focusMinutes, 180))
        let clampedBreakMinutes = max(1, min(breakMinutes, 60))

        guard preset.focusMinutes != clampedFocusMinutes || preset.breakMinutes != clampedBreakMinutes else {
            return
        }

        let targetIndex: Int
        if let currentCustomIndex = customPresets.firstIndex(where: { $0.id == preset.id }) {
            targetIndex = currentCustomIndex
        } else {
            targetIndex = 0
        }

        guard customPresets.indices.contains(targetIndex) else { return }

        var updatedPreset = customPresets[targetIndex]
        updatedPreset.focusMinutes = clampedFocusMinutes
        updatedPreset.breakMinutes = clampedBreakMinutes

        customPresets[targetIndex] = updatedPreset
        persistCustomPresets()
        focusDurationOverrideSeconds = nil
        breakDurationOverrideSeconds = nil
        selectPreset(updatedPreset)
    }

    func updateCurrentDurations(focusSeconds: Int, breakSeconds: Int) {
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
        longBreakDurationOverrideSeconds = nil
        remainingSeconds = clampedFocusSeconds
        recordedFocusSecondsForCurrentPhase = 0
        wasManuallyPaused = false
        persistRuntimeState()
    }

    func updateLongBreakDuration(minutes: Int) {
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

    func updateLongBreakDuration(seconds: Int) {
        let clamped = max(1, min(seconds, 60 * 60))
        guard longBreakDurationSeconds != clamped else { return }
        longBreakDurationOverrideSeconds = clamped
        if phase == .longBreak && !hasActiveSession {
            remainingSeconds = clamped
        }
        persistRuntimeState()
    }

    func updateSessionsBeforeLongBreak(count: Int) {
        let clamped = max(1, min(count, 12))
        guard sessionsBeforeLongBreakOverride != clamped else { return }
        sessionsBeforeLongBreakOverride = clamped
        persistRuntimeState()
    }

    func setFocusMode(_ mode: PomodoroFocusMode) {
        guard focusMode != mode else { return }
        focusMode = mode
        isFullscreenActive = false
        if isRunning {
            pause()
        }
    }

    private func evaluateFullscreenState() {
        switch focusMode {
        case .off:
            isFullscreenActive = false
        case .zen:
            isFullscreenActive = true
        case .strict:
            isFullscreenActive = (phase == .shortBreak || phase == .longBreak)
        }
    }

    func exitFullscreen() {
        isFullscreenActive = false
        if isRunning {
            pause()
        }
    }

    func shutdown() {
        recordCurrentFocusProgressIfNeeded(referenceDate: nowProvider())
        flushPendingPersistence()
        persistSettingsImmediately()
        persistRuntimeStateImmediately()
        persistTasksImmediately()
        isFullscreenActive = false
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
        let lang = appLanguageProvider.currentLanguage
        let title = Localization.get(phase.rawValue, lang: lang)
        var body = phaseReminder.text
        if !phaseReminder.author.isEmpty {
            body += "\n" + phaseReminder.author
        }
        AppNotificationManager.sendNotification(
            title: title,
            body: body,
            identifier: "notch.pomodoro.phase-start.\(UUID().uuidString)"
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
                persistTasks()
            }
            
            phase = nextBreakPhase
        } else {
            phase = .focus
        }

        remainingSeconds = duration(for: phase, preset: preset)
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
                SoundManager.playFocusComplete()
            case .shortBreak, .longBreak:
                SoundManager.playBreakComplete()
            }
        }

        advancePhase(continueRunning: true, postTransitionNotification: postTransitionNotification)
    }

    private func duration(for phase: PomodoroPhase, preset: PomodoroPreset) -> Int {
        switch phase {
        case .focus:
            return focusDurationOverrideSeconds ?? (preset.focusMinutes * 60)
        case .shortBreak:
            return breakDurationOverrideSeconds ?? (preset.breakMinutes * 60)
        case .longBreak:
            return longBreakDurationOverrideSeconds ?? (preset.longBreakMinutes * 60)
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

        let elapsedFocusSeconds = max(duration(for: .focus, preset: preset) - remainingSeconds(at: referenceDate), 0)
        let delta = elapsedFocusSeconds - recordedFocusSecondsForCurrentPhase
        guard delta > 0 else { return }

        learningStatsRecorder.record(seconds: delta, source: .pomodoro)
        recordedFocusSecondsForCurrentPhase += delta
    }

    private func persistCustomPresets() {
        guard let encoded = try? JSONEncoder().encode(customPresets) else { return }
        userDefaults.set(encoded, forKey: Self.customPresetsDefaultsKey)
    }

    private func persistSelectedPresetID() {
        userDefaults.set(preset.id, forKey: Self.selectedPresetIDDefaultsKey)
    }

    private static func loadCustomPresets(from userDefaults: UserDefaults) -> [PomodoroPreset] {
        guard let data = userDefaults.data(forKey: customPresetsDefaultsKey),
              let decodedPresets = try? JSONDecoder().decode([PomodoroPreset].self, from: data),
              decodedPresets.count == PomodoroPreset.defaultCustomPresets.count else {
            return PomodoroPreset.defaultCustomPresets
        }

        return decodedPresets.enumerated().map { index, preset in
            var normalizedPreset = preset
            normalizedPreset.isCustom = true
            normalizedPreset.id = PomodoroPreset.defaultCustomPresets[index].id
            if normalizedPreset.title.isEmpty {
                normalizedPreset.title = PomodoroPreset.defaultCustomPresets[index].title
            }
            return normalizedPreset
        }
    }

    private static func resolvePreset(
        matching presetID: String?,
        customPresets: [PomodoroPreset]
    ) -> PomodoroPreset? {
        guard let presetID else { return nil }
        return (PomodoroPreset.builtInPresets + customPresets).first { $0.id == presetID }
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
        userDefaults.set(focusMode.rawValue, forKey: Self.focusModeKey)
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
                postPhaseStartedNotification()
                return
            }

            let nextState = restoredTransition(
                after: restoredPhase,
                completedFocusSessions: restoredCompletedFocusSessions
            )
            restoredPhase = nextState.phase
            restoredCompletedFocusSessions = nextState.completedFocusSessions
            restoredPhaseEndDate = restoredPhaseEndDate.addingTimeInterval(
                TimeInterval(duration(for: restoredPhase, preset: preset))
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
        remainingSeconds = duration(for: phase, preset: preset)
        persistRuntimeState()
    }

    private func restartPhase() {
        start(force: true)
    }

    private func clampedRemainingSeconds(_ seconds: Int, for phase: PomodoroPhase, activeSession: Bool) -> Int {
        let phaseDuration = duration(for: phase, preset: preset)
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

    private static let customPresetsDefaultsKey = "NotchPomodoroCustomPresets"
    private static let selectedPresetIDDefaultsKey = "NotchPomodoroSelectedPresetID"
    private static let autoStartBreaksKey = "NotchPomodoroAutoStartBreaks"
    private static let autoStartPomodorosKey = "NotchPomodoroAutoStartPomodoros"
    private static let focusDurationOverrideSecondsKey = "NotchPomodoroFocusDurationOverrideSeconds"
    private static let breakDurationOverrideSecondsKey = "NotchPomodoroBreakDurationOverrideSeconds"
    private static let longBreakDurationOverrideSecondsKey = "NotchPomodoroLongBreakDurationOverrideSeconds"
    private static let sessionsBeforeLongBreakOverrideKey = "NotchPomodoroSessionsBeforeLongBreakOverride"
    private static let runtimeStateDefaultsKey = "NotchPomodoroRuntimeState"
    private static let focusModeKey = "NotchPomodoroFocusMode"
    private static let tasksKey = "NotchPomodoroTasks"
    private static let selectedTaskIdKey = "NotchPomodoroSelectedTaskId"

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
