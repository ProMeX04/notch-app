import AppKit
import Foundation
import SwiftUI

enum PomodoroPhase: String {
    case focus = "Focus"
    case shortBreak = "Break"

    var symbolName: String {
        switch self {
        case .focus:
            return "timer"
        case .shortBreak:
            return "cup.and.saucer.fill"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .focus:
            return .systemOrange
        case .shortBreak:
            return .systemGreen
        }
    }
}

struct PomodoroPreset: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var focusMinutes: Int
    var breakMinutes: Int
    var isCustom: Bool

    var chipTitle: String {
        "\(focusMinutes)/\(breakMinutes)"
    }

    static let sprint = PomodoroPreset(
        id: "sprint",
        title: "Sprint",
        focusMinutes: 15,
        breakMinutes: 3,
        isCustom: false
    )

    static let classic = PomodoroPreset(
        id: "classic",
        title: "Classic",
        focusMinutes: 25,
        breakMinutes: 5,
        isCustom: false
    )

    static let deep = PomodoroPreset(
        id: "deep",
        title: "Deep",
        focusMinutes: 50,
        breakMinutes: 10,
        isCustom: false
    )

    static let builtInPresets = [sprint, classic, deep]
    static let defaultCustomPresets = [
        PomodoroPreset(id: "custom-1", title: "Custom 1", focusMinutes: 20, breakMinutes: 5, isCustom: true),
        PomodoroPreset(id: "custom-2", title: "Custom 2", focusMinutes: 45, breakMinutes: 10, isCustom: true),
        PomodoroPreset(id: "custom-3", title: "Custom 3", focusMinutes: 90, breakMinutes: 15, isCustom: true),
    ]
}

@MainActor
final class PomodoroViewModel: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var preset: PomodoroPreset
    @Published private(set) var customPresets: [PomodoroPreset]
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var hasActiveSession = false
    @Published private(set) var completedFocusSessions = 0
    @Published private(set) var focusDurationOverrideSeconds: Int?
    @Published private(set) var breakDurationOverrideSeconds: Int?

    private var phaseCompletionTask: Task<Void, Never>?
    private var phaseEndDate: Date?
    private let userDefaults: UserDefaults
    private let learningStatsStore: LearningStatsStore
    private var recordedFocusSecondsForCurrentPhase = 0

    init(
        userDefaults: UserDefaults = .standard,
        learningStatsStore: LearningStatsStore
    ) {
        self.userDefaults = userDefaults
        self.learningStatsStore = learningStatsStore
        let restoredCustomPresets = Self.loadCustomPresets(from: userDefaults)
        customPresets = restoredCustomPresets

        let selectedPresetID = userDefaults.string(forKey: Self.selectedPresetIDDefaultsKey)
        let resolvedPreset = Self.resolvePreset(
            matching: selectedPresetID,
            customPresets: restoredCustomPresets
        ) ?? .classic

        preset = resolvedPreset
        remainingSeconds = resolvedPreset.focusMinutes * 60
    }

    var availablePresets: [PomodoroPreset] {
        PomodoroPreset.builtInPresets + customPresets
    }

    var focusMinutes: Int {
        preset.focusMinutes
    }

    var breakMinutes: Int {
        preset.breakMinutes
    }

    var focusDurationSeconds: Int {
        focusDurationOverrideSeconds ?? (preset.focusMinutes * 60)
    }

    var breakDurationSeconds: Int {
        breakDurationOverrideSeconds ?? (preset.breakMinutes * 60)
    }

    var showCompactIndicator: Bool {
        hasActiveSession || isRunning
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

        return "Ready for your next \(DurationParser.displayString(for: focusDurationSeconds)) session"
    }

    var nextPhaseLine: String {
        let nextPhase = phase == .focus ? "Break" : "Focus"
        let nextDurationSeconds = phase == .focus ? breakDurationSeconds : focusDurationSeconds
        return "Up next: \(nextPhase) \(DurationParser.displayString(for: nextDurationSeconds))"
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
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }

        hasActiveSession = true
        isRunning = true
        phaseEndDate = .now.addingTimeInterval(TimeInterval(remainingSeconds))
        startPhaseCompletionTask()
    }

    func pause() {
        guard isRunning else { return }

        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        remainingSeconds = remainingSeconds(at: .now)
        isRunning = false
        phaseEndDate = nil
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
    }

    func reset() {
        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus, preset: preset)
        recordedFocusSecondsForCurrentPhase = 0
        focusDurationOverrideSeconds = nil
        breakDurationOverrideSeconds = nil
    }

    func skipPhase() {
        let shouldContinueRunning = isRunning
        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        advancePhase(continueRunning: shouldContinueRunning)
    }

    func selectPreset(_ preset: PomodoroPreset) {
        guard self.preset != preset else { return }

        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        self.preset = preset
        persistSelectedPresetID()
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        remainingSeconds = duration(for: .focus, preset: preset)
        recordedFocusSecondsForCurrentPhase = 0
        focusDurationOverrideSeconds = nil
        breakDurationOverrideSeconds = nil
    }

    func updateCustomPreset(slotIndex: Int, focusMinutes: Int, breakMinutes: Int) {
        guard customPresets.indices.contains(slotIndex) else { return }

        let clampedFocusMinutes = max(5, min(focusMinutes, 180))
        let clampedBreakMinutes = max(1, min(breakMinutes, 60))
        var updatedPreset = customPresets[slotIndex]
        updatedPreset.focusMinutes = clampedFocusMinutes
        updatedPreset.breakMinutes = clampedBreakMinutes

        customPresets[slotIndex] = updatedPreset
        persistCustomPresets()
        selectPreset(updatedPreset)
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

        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
        phaseEndDate = nil
        isRunning = false
        hasActiveSession = false
        completedFocusSessions = 0
        phase = .focus
        focusDurationOverrideSeconds = clampedFocusSeconds
        breakDurationOverrideSeconds = clampedBreakSeconds
        remainingSeconds = clampedFocusSeconds
        recordedFocusSecondsForCurrentPhase = 0
    }

    func shutdown() {
        recordCurrentFocusProgressIfNeeded(referenceDate: .now)
        phaseCompletionTask?.cancel()
        phaseCompletionTask = nil
    }

    private func advancePhase(continueRunning: Bool) {
        if phase == .focus {
            recordCurrentFocusProgressIfNeeded(referenceDate: .now)
            completedFocusSessions += 1
            phase = .shortBreak
        } else {
            phase = .focus
        }

        remainingSeconds = duration(for: phase, preset: preset)
        phaseEndDate = nil
        hasActiveSession = continueRunning || hasActiveSession
        recordedFocusSecondsForCurrentPhase = 0

        if continueRunning {
            isRunning = false
            start()
        } else {
            isRunning = false
        }
    }

    private func startPhaseCompletionTask() {
        phaseCompletionTask?.cancel()

        let duration = remainingSeconds(at: .now)

        phaseCompletionTask = Task { @MainActor [weak self] in
            guard let self, duration > 0 else { return }

            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self.isRunning else { return }

            let finishedPhase = self.phase
            self.remainingSeconds = 0
            
            if finishedPhase == .focus {
                AppNotificationManager.sendNotification(title: "Focus Session Complete", body: "Time for a break!")
            } else {
                AppNotificationManager.sendNotification(title: "Break Complete", body: "Time to get back to work.")
            }

            self.advancePhase(continueRunning: true)
        }
    }

    private func duration(for phase: PomodoroPhase, preset: PomodoroPreset) -> Int {
        switch phase {
        case .focus:
            return focusDurationOverrideSeconds ?? (preset.focusMinutes * 60)
        case .shortBreak:
            return breakDurationOverrideSeconds ?? (preset.breakMinutes * 60)
        }
    }

    private func recordCurrentFocusProgressIfNeeded(referenceDate: Date) {
        guard phase == .focus else { return }

        let elapsedFocusSeconds = max(duration(for: .focus, preset: preset) - remainingSeconds(at: referenceDate), 0)
        let delta = elapsedFocusSeconds - recordedFocusSecondsForCurrentPhase
        guard delta > 0 else { return }

        learningStatsStore.record(seconds: delta, source: .pomodoro)
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

    private static let customPresetsDefaultsKey = "NotchPomodoroCustomPresets"
    private static let selectedPresetIDDefaultsKey = "NotchPomodoroSelectedPresetID"
}
