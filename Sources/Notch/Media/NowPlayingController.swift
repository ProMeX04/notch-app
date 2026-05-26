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
        SystemAudioOutput.supportsVolumeControl()
    }

    var supportsFavorite: Bool {
        false
    }

    private let adapterScriptURL: URL
    private let adapterFrameworkURL: URL
    private let commandRunner: MediaRemoteCommandRunner
    private let mediaRemoteSetElapsedTime: (@convention(c) (Double) -> Void)?
    private let timestampFormatter = ISO8601DateFormatter()

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var isShuttingDown = false

    init?() {
        guard let adapterScriptURL = ProbeResources.mediaRemoteAdapterScriptURL else {
            NotchLog.mediaRemote.error("NowPlaying disabled: missing mediaremote-adapter.pl")
            return nil
        }
        guard let adapterFrameworkURL = ProbeResources.mediaRemoteFrameworkURL else {
            NotchLog.mediaRemote.error("NowPlaying disabled: missing MediaRemoteAdapter.framework")
            return nil
        }

        self.adapterScriptURL = adapterScriptURL
        self.adapterFrameworkURL = adapterFrameworkURL
        commandRunner = MediaRemoteCommandRunner(
            adapterScriptURL: adapterScriptURL,
            adapterFrameworkURL: adapterFrameworkURL
        )
        mediaRemoteSetElapsedTime = Self.loadMediaRemoteSetElapsedTime()

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
        guard !isShuttingDown else { return }
        isShuttingDown = true

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

    private var hasRunningSourceApp: Bool {
        guard !playbackState.bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: playbackState.bundleIdentifier).isEmpty
    }

    func play() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command play ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 0)
    }

    func pause() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command pause ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 1)
    }

    func togglePlay() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command togglePlay ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 2)
    }

    /// `kMRStop` — dừng phát; hành vi tùy app (Music/Spotify thường dừng và giữ track).
    func stop() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command stop ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 3)
    }

    func nextTrack() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command nextTrack ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 4)
    }

    func previousTrack() async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command previousTrack ignored: no metadata/running app")
            return
        }
        await commandRunner.send(command: 5)
    }

    func seek(to time: Double) async {
        guard playbackState.hasTrackMetadata || hasRunningSourceApp else {
            NotchLog.mediaRemote.debug("Command seek ignored: no metadata/running app")
            return
        }
        let clampedTime = max(0, time)
        if let mediaRemoteSetElapsedTime {
            NotchLog.mediaRemote.debug("Media seek started: direct position=\(clampedTime)")
            mediaRemoteSetElapsedTime(clampedTime)
        } else {
            NotchLog.mediaRemote.debug("Media seek using adapter fallback: position=\(clampedTime)")
            await commandRunner.seek(to: clampedTime)
        }
    }

    func isActive() -> Bool {
        true
    }

    func setVolume(_ level: Double) async {
        do {
            try SystemAudioOutput.setVolume(level)
            playbackState.volume = (try? SystemAudioOutput.currentVolume()) ?? max(0.0, min(1.0, level))
        } catch {
            NotchLog.mediaRemote.error("Failed to set system volume: \(error.localizedDescription)")
        }
    }

    private func setupNowPlayingObserver() async {
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            adapterScriptURL.path,
            adapterFrameworkURL.path,
            "stream",
            "--debounce=100",
        ]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        process.terminationHandler = { process in
            if process.terminationStatus != 0 || process.terminationReason != .exit {
                NotchLog.mediaRemote.error("MediaRemote adapter exited with status \(process.terminationStatus), reason \(process.terminationReason.rawValue)")
            }
            Task {
                await pipeHandler.close()
            }
        }

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
        let previousState = playbackState
        let newPlaybackState = NowPlayingStateReducer.reduce(
            previousState: previousState,
            update: update,
            timestampFormatter: timestampFormatter
        )

        guard newPlaybackState != previousState else { return }
        if newPlaybackState.isPlaying != previousState.isPlaying ||
            newPlaybackState.hasMediaContext != previousState.hasMediaContext {
            NotchLog.mediaRemote.debug(
                "NowPlaying state changed: playing=\(newPlaybackState.isPlaying), mediaContext=\(newPlaybackState.hasMediaContext)"
            )
        }
        playbackState = newPlaybackState
    }

    private func fetchFavoriteStateIfSupported() async {}

    func setFavorite(_ favorite: Bool) async {}

    #if DEBUG
    func setPlaybackStateForTesting(_ state: PlaybackState) {
        self.playbackState = state
    }
    #endif

    private static func loadMediaRemoteSetElapsedTime() -> (@convention(c) (Double) -> Void)? {
        let frameworkURL = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, frameworkURL),
              let pointer = CFBundleGetFunctionPointerForName(
                  bundle,
                  "MRMediaRemoteSetElapsedTime" as CFString
              ) else {
            NotchLog.mediaRemote.error("Direct media seek unavailable; using adapter fallback")
            return nil
        }

        return unsafeBitCast(pointer, to: (@convention(c) (Double) -> Void).self)
    }
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
            guard !data.isEmpty else {
                NotchLog.mediaRemote.info("MediaRemote adapter stream ended")
                break
            }

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

private actor MediaRemoteCommandRunner {
    private let adapterScriptURL: URL
    private let adapterFrameworkURL: URL

    init(adapterScriptURL: URL, adapterFrameworkURL: URL) {
        self.adapterScriptURL = adapterScriptURL
        self.adapterFrameworkURL = adapterFrameworkURL
    }

    func send(command: Int) {
        run(arguments: ["send", String(command)], label: "send \(command)")
    }

    func seek(to time: Double) {
        let microseconds = Int64((max(0, time) * 1_000_000).rounded())
        run(arguments: ["seek", String(microseconds)], label: "seek")
    }

    private func run(arguments: [String], label: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapterScriptURL.path, adapterFrameworkURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        NotchLog.mediaRemote.debug("Media command started: \(label, privacy: .public)")

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && process.terminationReason == .exit {
                NotchLog.mediaRemote.debug("Media command completed: \(label, privacy: .public)")
            } else {
                NotchLog.mediaRemote.error(
                    "Media command failed: \(label, privacy: .public), status=\(process.terminationStatus)"
                )
            }
        } catch {
            NotchLog.mediaRemote.error(
                "Media command launch failed: \(label, privacy: .public), error=\(error.localizedDescription)"
            )
        }
    }
}
