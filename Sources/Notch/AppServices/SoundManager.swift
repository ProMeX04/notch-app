import AppKit

enum FocusTransitionSoundOption: String, CaseIterable, Identifiable {
    case thoribass
    case nouncement

    static let defaultOption: Self = .thoribass

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        case .thoribass:
            return "thoribass"
        case .nouncement:
            return "nouncement"
        }
    }

    var displayName: String {
        switch self {
        case .thoribass:
            return "Thoribass"
        case .nouncement:
            return "Nouncement"
        }
    }

    var next: Self {
        let options = Self.allCases
        guard let index = options.firstIndex(of: self) else {
            return Self.defaultOption
        }

        return options[(index + 1) % options.count]
    }
}

@MainActor
struct SoundManager {
    static let focusTransitionSoundKey = "NotchPomodoroFocusTransitionSound"

    private static var focusSoundCache: [FocusTransitionSoundOption: NSSound] = [:]

    static var selectedFocusTransitionSound: FocusTransitionSoundOption {
        let storedValue = UserDefaults.standard.string(forKey: focusTransitionSoundKey)
        return FocusTransitionSoundOption(rawValue: storedValue ?? "") ?? .defaultOption
    }

    static func cycleFocusTransitionSound() -> FocusTransitionSoundOption {
        let nextSound = selectedFocusTransitionSound.next
        UserDefaults.standard.set(nextSound.rawValue, forKey: focusTransitionSoundKey)
        return nextSound
    }

    static func previewFocusTransitionSound(_ option: FocusTransitionSoundOption? = nil) {
        playFocusTransitionSound(option ?? selectedFocusTransitionSound)
    }

    /// Plays the selected bundled sound for focus phase transitions.
    static func playFocusComplete() {
        playFocusTransitionSound(selectedFocusTransitionSound)
    }

    /// Uses the same selected bundled sound when a break phase completes.
    static func playBreakComplete() {
        playFocusTransitionSound(selectedFocusTransitionSound)
    }

    /// Subtle sound when a button is clicked or timer toggles
    static func playNotification() {
        let sound = NSSound(named: "Tink")
        sound?.stop()
        sound?.play()
    }

    private static func playFocusTransitionSound(_ option: FocusTransitionSoundOption) {
        guard let sound = bundledSound(for: option) else {
            NSSound(named: "Hero")?.play()
            return
        }

        sound.stop()
        sound.play()
    }

    private static func bundledSound(for option: FocusTransitionSoundOption) -> NSSound? {
        if let cachedSound = focusSoundCache[option] {
            return cachedSound
        }

        guard let url = Bundle.module.url(
            forResource: option.resourceName,
            withExtension: "wav",
            subdirectory: "FocusSounds"
        ) else {
            return nil
        }

        guard let sound = NSSound(contentsOf: url, byReference: false) else {
            return nil
        }

        focusSoundCache[option] = sound
        return sound
    }
}
