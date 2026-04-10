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

    private let mediaRemoteBundle: CFBundle
    private let mediaRemoteSendCommand: @convention(c) (Int, AnyObject?) -> Void
    private let mediaRemoteSetElapsedTime: @convention(c) (Double) -> Void
    private let mediaRemoteSetShuffleMode: @convention(c) (Int) -> Void
    private let mediaRemoteSetRepeatMode: @convention(c) (Int) -> Void
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
            ),
            let setShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSetShuffleMode" as CFString
            ),
            let setRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSetRepeatMode" as CFString
            )
        else {
            return nil
        }

        mediaRemoteBundle = bundle
        mediaRemoteSendCommand = unsafeBitCast(sendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        mediaRemoteSetElapsedTime = unsafeBitCast(setElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        mediaRemoteSetShuffleMode = unsafeBitCast(setShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        mediaRemoteSetRepeatMode = unsafeBitCast(setRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

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

    func toggleShuffle() async {
        guard canControlPlayback else { return }
        mediaRemoteSetShuffleMode(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    func toggleRepeat() async {
        guard canControlPlayback else { return }
        let newRepeatMode = playbackState.repeatMode == .off ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        mediaRemoteSetRepeatMode(newRepeatMode)
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

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)

        newPlaybackState.title = payload.title ?? (diff ? playbackState.title : "Nothing Playing")
        newPlaybackState.artist = payload.artist ?? (diff ? playbackState.artist : "Notch")
        newPlaybackState.album = payload.album ?? (diff ? playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? playbackState.duration : 0)

        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(playbackState.lastUpdated)
                newPlaybackState.currentTime = playbackState.currentTime + (playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if diff {
            newPlaybackState.isShuffled = playbackState.isShuffled
        }

        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if diff {
            newPlaybackState.repeatMode = playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if diff {
            newPlaybackState.artwork = playbackState.artwork
        }

        if let dateString = payload.timestamp,
           let date = timestampFormatter.date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if diff {
            newPlaybackState.lastUpdated = playbackState.lastUpdated
        } else {
            newPlaybackState.lastUpdated = .now
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier =
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? playbackState.bundleIdentifier : "")
        newPlaybackState.volume = payload.volume ?? (diff ? playbackState.volume : 0.5)

        guard newPlaybackState != playbackState else { return }
        playbackState = newPlaybackState
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
        !playbackState.title.isEmpty && playbackState.title != "Nothing Playing"
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
    let shuffleMode: Int?
    let repeatMode: Int?
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
