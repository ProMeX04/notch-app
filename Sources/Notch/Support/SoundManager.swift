import AppKit

struct SoundManager {
    /// Plays most appropriate system sound for focus complete
    static func playFocusComplete() {
        NSSound(named: "Hero")?.play()
    }

    /// Plays most appropriate system sound for break complete
    static func playBreakComplete() {
        NSSound(named: "Ping")?.play()
    }
    
    /// Subtle sound when a button is clicked or timer toggles
    static func playNotification() {
        let sound = NSSound(named: "Tink")
        sound?.stop()
        sound?.play()
    }
}
