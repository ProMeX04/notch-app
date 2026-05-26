import Foundation

struct NowPlayingUpdate: Decodable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Decodable, Sendable {
    let title: NowPlayingPayloadField<String>
    let artist: NowPlayingPayloadField<String>
    let album: NowPlayingPayloadField<String>
    let duration: NowPlayingPayloadField<Double>
    let elapsedTime: NowPlayingPayloadField<Double>
    let prohibitsSkip: NowPlayingPayloadField<Bool>
    let supportsFastForward15Seconds: NowPlayingPayloadField<Bool>
    let supportsRewind15Seconds: NowPlayingPayloadField<Bool>
    let artworkData: NowPlayingPayloadField<String>
    let timestamp: NowPlayingPayloadField<String>
    let playbackRate: NowPlayingPayloadField<Double>
    let playing: NowPlayingPayloadField<Bool>
    let parentApplicationBundleIdentifier: NowPlayingPayloadField<String>
    let bundleIdentifier: NowPlayingPayloadField<String>
    let volume: NowPlayingPayloadField<Double>

    private enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case duration
        case elapsedTime
        case prohibitsSkip
        case supportsFastForward15Seconds
        case supportsRewind15Seconds
        case artworkData
        case timestamp
        case playbackRate
        case playing
        case parentApplicationBundleIdentifier
        case bundleIdentifier
        case volume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.field(forKey: .title)
        artist = try container.field(forKey: .artist)
        album = try container.field(forKey: .album)
        duration = try container.field(forKey: .duration)
        elapsedTime = try container.field(forKey: .elapsedTime)
        prohibitsSkip = try container.field(forKey: .prohibitsSkip)
        supportsFastForward15Seconds = try container.field(forKey: .supportsFastForward15Seconds)
        supportsRewind15Seconds = try container.field(forKey: .supportsRewind15Seconds)
        artworkData = try container.field(forKey: .artworkData)
        timestamp = try container.field(forKey: .timestamp)
        playbackRate = try container.field(forKey: .playbackRate)
        playing = try container.field(forKey: .playing)
        parentApplicationBundleIdentifier = try container.field(forKey: .parentApplicationBundleIdentifier)
        bundleIdentifier = try container.field(forKey: .bundleIdentifier)
        volume = try container.field(forKey: .volume)
    }
}

enum NowPlayingPayloadField<Value: Decodable & Sendable>: Sendable {
    case missing
    case null
    case value(Value)
}

private extension KeyedDecodingContainer {
    func field<T: Decodable & Sendable>(forKey key: Key) throws -> NowPlayingPayloadField<T> {
        guard contains(key) else { return .missing }
        guard try !decodeNil(forKey: key) else { return .null }
        return .value(try decode(T.self, forKey: key))
    }
}

enum NowPlayingStateReducer {
    static func reduce(
        previousState: PlaybackState,
        update: NowPlayingUpdate,
        timestampFormatter: ISO8601DateFormatter
    ) -> PlaybackState {
        let payload = update.payload
        let isDiff = update.diff ?? false
        var state = PlaybackState(
            bundleIdentifier: bundleIdentifier(
                from: payload,
                previousValue: previousState.bundleIdentifier,
                isDiff: isDiff
            )
        )

        state.title = value(payload.title, previous: previousState.title, empty: "Nothing Playing", isDiff: isDiff)
        state.artist = value(payload.artist, previous: previousState.artist, empty: "Notch", isDiff: isDiff)
        state.album = value(payload.album, previous: previousState.album, empty: "", isDiff: isDiff)
        state.duration = value(payload.duration, previous: previousState.duration, empty: 0, isDiff: isDiff)
        state.currentTime = currentTime(from: payload, previousState: previousState, isDiff: isDiff)
        state.artwork = artwork(from: payload, previousValue: previousState.artwork, isDiff: isDiff)
        state.lastUpdated = timestamp(
            from: payload,
            previousValue: previousState.lastUpdated,
            isDiff: isDiff,
            timestampFormatter: timestampFormatter
        )
        state.playbackRate = value(payload.playbackRate, previous: previousState.playbackRate, empty: 1.0, isDiff: isDiff)
        state.isPlaying = value(payload.playing, previous: previousState.isPlaying, empty: false, isDiff: isDiff)
        state.volume = value(payload.volume, previous: previousState.volume, empty: 0.5, isDiff: isDiff)
        state.prohibitsSkip = value(payload.prohibitsSkip, previous: previousState.prohibitsSkip, empty: false, isDiff: isDiff)
        state.supportsFastForward15Seconds = optionalValue(
            payload.supportsFastForward15Seconds,
            previous: previousState.supportsFastForward15Seconds,
            isDiff: isDiff
        )
        state.supportsRewind15Seconds = optionalValue(
            payload.supportsRewind15Seconds,
            previous: previousState.supportsRewind15Seconds,
            isDiff: isDiff
        )

        return state
    }

    private static func value<T>(
        _ field: NowPlayingPayloadField<T>,
        previous: T,
        empty: T,
        isDiff: Bool
    ) -> T {
        switch field {
        case .value(let value):
            return value
        case .null:
            return empty
        case .missing:
            return isDiff ? previous : empty
        }
    }

    private static func optionalValue<T>(
        _ field: NowPlayingPayloadField<T>,
        previous: T?,
        isDiff: Bool
    ) -> T? {
        switch field {
        case .value(let value):
            return value
        case .null:
            return nil
        case .missing:
            return isDiff ? previous : nil
        }
    }

    private static func bundleIdentifier(
        from payload: NowPlayingPayload,
        previousValue: String,
        isDiff: Bool
    ) -> String {
        if case .value(let bundleIdentifier) = payload.parentApplicationBundleIdentifier {
            return bundleIdentifier
        }
        if case .value(let bundleIdentifier) = payload.bundleIdentifier {
            return bundleIdentifier
        }
        if case .null = payload.parentApplicationBundleIdentifier {
            return ""
        }
        if case .null = payload.bundleIdentifier {
            return ""
        }
        return isDiff ? previousValue : ""
    }

    private static func currentTime(
        from payload: NowPlayingPayload,
        previousState: PlaybackState,
        isDiff: Bool
    ) -> Double {
        switch payload.elapsedTime {
        case .value(let elapsedTime):
            return elapsedTime
        case .null:
            return 0
        case .missing:
            guard isDiff else { return 0 }
            guard case .value(false) = payload.playing else {
                return previousState.currentTime
            }
            let elapsed = Date().timeIntervalSince(previousState.lastUpdated)
            return previousState.currentTime + (previousState.playbackRate * elapsed)
        }
    }

    private static func artwork(
        from payload: NowPlayingPayload,
        previousValue: Data?,
        isDiff: Bool
    ) -> Data? {
        switch payload.artworkData {
        case .value(let encodedData):
            return Data(base64Encoded: encodedData.trimmingCharacters(in: .whitespacesAndNewlines))
        case .null:
            return nil
        case .missing:
            return isDiff ? previousValue : nil
        }
    }

    private static func timestamp(
        from payload: NowPlayingPayload,
        previousValue: Date,
        isDiff: Bool,
        timestampFormatter: ISO8601DateFormatter
    ) -> Date {
        switch payload.timestamp {
        case .value(let timestamp):
            return timestampFormatter.date(from: timestamp) ?? (isDiff ? previousValue : .now)
        case .null:
            return .now
        case .missing:
            return isDiff ? previousValue : .now
        }
    }
}
