import AppKit
import Combine
import Foundation

@MainActor
final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: ""
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        playbackState.bundleIdentifier == "com.apple.Music"
    }

    private let mediaRemoteSendCommand: @convention(c) (Int, AnyObject?) -> Void
    private let mediaRemoteSetElapsedTime: @convention(c) (Double) -> Void
    private let timestampFormatter = ISO8601DateFormatter()

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
            ),
            let sendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSendCommand" as CFString
            ),
            let setElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSetElapsedTime" as CFString
            )
        else {
            return nil
        }

        mediaRemoteSendCommand = unsafeBitCast(sendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        mediaRemoteSetElapsedTime = unsafeBitCast(setElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shutdown()
            }
        }

        Task {
            await setupNowPlayingObserver()
        }
    }

    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    func shutdown() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }

        streamTask?.cancel()
        streamTask = nil

        if let process, process.isRunning {
            process.terminate()

            Task.detached { [weak process] in
                try? await Task.sleep(for: .seconds(2))
                if let process, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        process = nil

        if let pipeHandler {
            Task {
                await pipeHandler.close()
            }
        }

        self.pipeHandler = nil
    }

    func play() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(0, nil)
    }

    func pause() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(1, nil)
    }

    func togglePlay() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(2, nil)
    }

    /// `kMRStop` — dừng phát; hành vi tùy app (Music/Spotify thường dừng và giữ track).
    func stop() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(3, nil)
    }

    func nextTrack() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(4, nil)
    }

    func previousTrack() async {
        guard canControlPlayback else { return }
        mediaRemoteSendCommand(5, nil)
    }

    func seek(to time: Double) async {
        guard canControlPlayback else { return }
        mediaRemoteSetElapsedTime(time)
    }

    func isActive() -> Bool {
        true
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        let bundleID = playbackState.bundleIdentifier

        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.spotify.client" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            if !runningApps.isEmpty {
                let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        }

        playbackState.volume = clampedLevel
    }

    private func setupNowPlayingObserver() async {
        let process = Process()
        let scriptURL = ProbeResources.mediaRemoteAdapterScriptURL
        let frameworkURL = ProbeResources.mediaRemoteFrameworkURL

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path, "stream"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            NotchLog.mediaRemote.error("Failed to launch mediaremote-adapter.pl: \(error.localizedDescription)")
        }
    }

    private func processJSONStream() async {
        guard let pipeHandler else { return }

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false
        let previousState = playbackState

        var newPlaybackState = PlaybackState(bundleIdentifier: previousState.bundleIdentifier)

        newPlaybackState.title = payload.title ?? (diff ? previousState.title : "Nothing Playing")
        newPlaybackState.artist = payload.artist ?? (diff ? previousState.artist : "Notch")
        newPlaybackState.album = payload.album ?? (diff ? previousState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? previousState.duration : 0)

        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(previousState.lastUpdated)
                newPlaybackState.currentTime = previousState.currentTime + (previousState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = previousState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if diff {
            newPlaybackState.artwork = previousState.artwork
        }

        if let dateString = payload.timestamp,
           let date = timestampFormatter.date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if diff {
            newPlaybackState.lastUpdated = previousState.lastUpdated
        } else {
            newPlaybackState.lastUpdated = .now
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? previousState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? previousState.isPlaying : false)
        newPlaybackState.bundleIdentifier =
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? previousState.bundleIdentifier : "")
        newPlaybackState.volume = payload.volume ?? (diff ? previousState.volume : 0.5)
        newPlaybackState.prohibitsSkip = payload.prohibitsSkip ?? (diff ? previousState.prohibitsSkip : false)
        newPlaybackState.supportsFastForward15Seconds =
            payload.supportsFastForward15Seconds ??
            (diff ? previousState.supportsFastForward15Seconds : nil)
        newPlaybackState.supportsRewind15Seconds =
            payload.supportsRewind15Seconds ??
            (diff ? previousState.supportsRewind15Seconds : nil)

        mergeTransitionalMediaState(
            into: &newPlaybackState,
            payload: payload,
            diff: diff,
            previousState: previousState
        )

        guard newPlaybackState != previousState else { return }
        playbackState = newPlaybackState
    }

    private func mergeTransitionalMediaState(
        into newPlaybackState: inout PlaybackState,
        payload: NowPlayingPayload,
        diff: Bool,
        previousState: PlaybackState
    ) {
        guard previousState.hasMediaContext else { return }

        if shouldPreservePreviousMetadata(
            for: newPlaybackState,
            payload: payload,
            diff: diff,
            previousState: previousState
        ) {
            newPlaybackState.title = previousState.title
            newPlaybackState.artist = previousState.artist
            newPlaybackState.album = previousState.album
            newPlaybackState.duration = previousState.duration
            newPlaybackState.bundleIdentifier = previousState.bundleIdentifier
        }

        if shouldPreservePreviousArtwork(
            for: newPlaybackState,
            payload: payload,
            previousState: previousState
        ) {
            newPlaybackState.artwork = previousState.artwork
        }
    }

    private func shouldPreservePreviousMetadata(
        for newPlaybackState: PlaybackState,
        payload: NowPlayingPayload,
        diff: Bool,
        previousState: PlaybackState
    ) -> Bool {
        guard !diff else { return false }
        guard previousState.hasTrackMetadata else { return false }
        guard !newPlaybackState.hasMediaContext else { return false }

        return payload.title == nil &&
            payload.artist == nil &&
            payload.album == nil &&
            payload.duration == nil &&
            payload.artworkData == nil &&
            payload.parentApplicationBundleIdentifier == nil &&
            payload.bundleIdentifier == nil
    }

    private func shouldPreservePreviousArtwork(
        for newPlaybackState: PlaybackState,
        payload: NowPlayingPayload,
        previousState: PlaybackState
    ) -> Bool {
        guard payload.artworkData == nil else { return false }
        guard previousState.artwork != nil else { return false }
        return newPlaybackState.hasMediaContext
    }

    private func fetchFavoriteStateIfSupported() async {
        guard playbackState.bundleIdentifier == "com.apple.Music" else { return }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application "Music"
            try
                return favorited of current track
            on error
                return false
            end try
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            var updated = playbackState
            updated.isFavorite = result.booleanValue
            playbackState = updated
        }
    }

    func setFavorite(_ favorite: Bool) async {
        guard playbackState.bundleIdentifier == "com.apple.Music" else { return }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application "Music"
            try
                set favorited of current track to \(favorite ? "true" : "false")
            end try
        end tell
        """

        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private var canControlPlayback: Bool {
        hasTrackMetadata || hasRunningSourceApp
    }

    private var hasTrackMetadata: Bool {
        playbackState.hasTrackMetadata
    }

    private var hasRunningSourceApp: Bool {
        guard !playbackState.bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: playbackState.bundleIdentifier
        ).isEmpty
    }
}

private struct NowPlayingUpdate: Codable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

private struct NowPlayingPayload: Codable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let prohibitsSkip: Bool?
    let supportsFastForward15Seconds: Bool?
    let supportsRewind15Seconds: Bool?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
}

private actor JSONLinesPipeHandler {
    private let pipe = Pipe()
    private let fileHandle: FileHandle
    private var buffer = ""

    init() {
        fileHandle = pipe.fileHandleForReading
    }

    func getPipe() -> Pipe {
        pipe
    }

    func readJSONLines<T: Decodable & Sendable>(
        as type: T.Type,
        onLine: @Sendable @escaping (T) async -> Void
    ) async {
        do {
            try await processLines(as: type, onLine: onLine)
        } catch {
            NotchLog.mediaRemote.error("Error processing JSON stream: \(error.localizedDescription)")
        }
    }

    private func processLines<T: Decodable & Sendable>(
        as type: T.Type,
        onLine: @Sendable @escaping (T) async -> Void
    ) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable & Sendable>(
        _ line: String,
        as type: T.Type,
        onLine: @Sendable @escaping (T) async -> Void
    ) async {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore malformed lines from the adapter.
        }
    }

    private func readData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            NotchLog.mediaRemote.error("Error closing pipe handler: \(error.localizedDescription)")
        }
    }
}
