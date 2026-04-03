import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
}

struct PlaybackState: Equatable {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "Nothing Playing"
    var artist: String = "Notch"
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = .distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false
}
