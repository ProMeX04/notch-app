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

        let runner = commandRunner
        Task {
            await runner.shutdown()
        }
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
        process.terminationHandler = { [weak self] process in
            if process.terminationStatus != 0 || process.terminationReason != .exit {
                NotchLog.mediaRemote.error("MediaRemote adapter exited with status \(process.terminationStatus), reason \(process.terminationReason.rawValue)")
            }
            Task { [weak self] in
                await pipeHandler.close()
                await self?.handleObserverTermination()
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

    private func handleObserverTermination() async {
        guard !isShuttingDown else { return }
        NotchLog.mediaRemote.warning("MediaRemote stream observer exited, restarting in 2 seconds...")

        self.streamTask?.cancel()
        self.streamTask = nil
        self.process = nil
        self.pipeHandler = nil

        try? await Task.sleep(for: .seconds(2))
        guard !isShuttingDown else { return }
        await setupNowPlayingObserver()
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
    private var continuation: AsyncStream<Data>.Continuation?

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
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }

        for await data in stream {
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

    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            continuation?.finish()
            continuation = nil
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

    private var process: Process?
    private var writeHandle: FileHandle?
    private var isShuttingDown = false

    init(adapterScriptURL: URL, adapterFrameworkURL: URL) {
        self.adapterScriptURL = adapterScriptURL
        self.adapterFrameworkURL = adapterFrameworkURL
        Task {
            await ensureProcessRunning()
        }
    }

    private func ensureProcessRunning() {
        if process != nil && process!.isRunning {
            return
        }

        cleanup()

        guard !isShuttingDown else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            adapterScriptURL.path,
            adapterFrameworkURL.path,
            "interactive"
        ]

        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.handleProcessTermination()
            }
        }

        self.writeHandle = pipe.fileHandleForWriting
        self.process = process

        do {
            try process.run()
            NotchLog.mediaRemote.info("MediaRemote interactive command runner launched")
        } catch {
            NotchLog.mediaRemote.error("Failed to launch MediaRemote interactive command runner: \(error.localizedDescription)")
            self.cleanup()
        }
    }

    private func handleProcessTermination() {
        guard !isShuttingDown else { return }
        NotchLog.mediaRemote.warning("MediaRemote interactive command runner exited, restarting...")
        self.cleanup()
        Task {
            try? await Task.sleep(for: .seconds(2))
            ensureProcessRunning()
        }
    }

    private func cleanup() {
        try? writeHandle?.close()
        writeHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    func shutdown() {
        isShuttingDown = true
        cleanup()
    }

    func send(command: Int) async {
        ensureProcessRunning()
        guard let writeHandle else {
            NotchLog.mediaRemote.error("Cannot send media command: process not running")
            return
        }

        let cmd = "send \(command)\n"
        if let data = cmd.data(using: .utf8) {
            do {
                try writeHandle.write(contentsOf: data)
                NotchLog.mediaRemote.debug("Sent interactive media command: \(command)")
            } catch {
                NotchLog.mediaRemote.error("Failed to write command to MediaRemote process: \(error.localizedDescription)")
                ensureProcessRunning()
            }
        }
    }

    func seek(to time: Double) async {
        ensureProcessRunning()
        guard let writeHandle else {
            NotchLog.mediaRemote.error("Cannot send seek command: process not running")
            return
        }

        let microseconds = Int64((max(0, time) * 1_000_000).rounded())
        let cmd = "seek \(microseconds)\n"
        if let data = cmd.data(using: .utf8) {
            do {
                try writeHandle.write(contentsOf: data)
                NotchLog.mediaRemote.debug("Sent interactive seek command: \(microseconds)")
            } catch {
                NotchLog.mediaRemote.error("Failed to write seek command to MediaRemote process: \(error.localizedDescription)")
                ensureProcessRunning()
            }
        }
    }
}
