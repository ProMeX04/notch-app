import Combine
import Foundation
import NotchFocusFeature
import SwiftUI

/// Opens the TOEIC study surface automatically while Focus is **running** and in the **focus** phase.
/// Break / pause / idle → hide study. No separate “open TOEIC” step.
@MainActor
final class TOEICFocusSessionBinder {
    static let shared = TOEICFocusSessionBinder()

    /// When false, Focus does not auto-open study (escape hatch).
    static let enabledKey = "notch.toeic.openDuringFocus"

    private var cancellables = Set<AnyCancellable>()
    private weak var pomodoro: PomodoroViewModel?

    private init() {}

    func bind(pomodoro: PomodoroViewModel) {
        cancellables.removeAll()
        self.pomodoro = pomodoro
        TOEICStudyViewModel.shared.pomodoro = pomodoro
        // Localhost bridge so Block Shorts can claim leisure minutes while Notch is open.
        TOEICBlockShortsBridge.shared.startServerIfNeeded()

        Publishers.CombineLatest(pomodoro.$isRunning, pomodoro.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning, phase in
                self?.sync(isRunning: isRunning, phase: phase)
            }
            .store(in: &cancellables)

        // When a break starts, convert banked study leisure into break time.
        pomodoro.$phase
            .receive(on: DispatchQueue.main)
            .sink { phase in
                if phase == .shortBreak || phase == .longBreak {
                    TOEICStudyViewModel.shared.applyLeisureBankToBreak()
                }
            }
            .store(in: &cancellables)

        // Initial state (e.g. restore after relaunch).
        sync(isRunning: pomodoro.isRunning, phase: pomodoro.phase)
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private func sync(isRunning: Bool, phase: PomodoroPhase) {
        guard isEnabled else {
            TOEICStudyWindowController.shared.hide()
            return
        }

        let shouldStudy = isRunning && phase == .focus
        if shouldStudy {
            let tint = phase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.72)
            TOEICStudyWindowController.shared.show(tint: tint)
        } else {
            TOEICStudyWindowController.shared.hide()
        }
    }
}
