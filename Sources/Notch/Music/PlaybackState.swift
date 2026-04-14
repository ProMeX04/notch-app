import Foundation

struct PlaybackState: Equatable {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "Nothing Playing"
    var artist: String = "Notch"
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var lastUpdated: Date = .distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false
    var prohibitsSkip: Bool = false
    var supportsFastForward15Seconds: Bool?
    var supportsRewind15Seconds: Bool?
}

extension PlaybackState {
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
    ]

    var hasTrackMetadata: Bool {
        !title.isEmpty && title != "Nothing Playing"
    }

    var hasMediaContext: Bool {
        hasTrackMetadata || !bundleIdentifier.isEmpty || isPlaying
    }

    var isBrowserSource: Bool {
        Self.browserBundleIdentifiers.contains(bundleIdentifier)
    }

    var canTogglePlayback: Bool {
        hasMediaContext
    }

    var canSkipToPreviousTrack: Bool {
        hasMediaContext && !prohibitsSkip && !isBrowserSource
    }

    var canSkipToNextTrack: Bool {
        hasMediaContext && !prohibitsSkip && !isBrowserSource
    }

    var canSkipBackward15Seconds: Bool {
        hasMediaContext && (supportsRewind15Seconds ?? (duration > 0))
    }

    var canSkipForward15Seconds: Bool {
        hasMediaContext && (supportsFastForward15Seconds ?? (duration > 0))
    }
}
