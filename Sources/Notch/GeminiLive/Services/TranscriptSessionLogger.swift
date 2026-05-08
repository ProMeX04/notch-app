import Foundation

/// Persists Gemini Live session transcripts to a per-session Markdown file under
/// `~/.notch/transcripts/`. Mutates state on the main actor; file I/O is dispatched to
/// a private serial queue so we never block the UI.
@MainActor
final class TranscriptSessionLogger {
    static let shared = TranscriptSessionLogger()

    private static let writeQueue = DispatchQueue(label: "dev.notch.transcript-logger", qos: .utility)

    private var fileURL: URL?

    /// Latest in-flight user voice transcript awaiting commit. Voice transcripts arrive as
    /// incremental snapshots; we commit when the model starts responding (or on session end).
    private var pendingUserText: String = ""

    /// Last user line we already wrote — used to suppress duplicates when the same transcript
    /// is replayed by the backend.
    private var loggedLastUserText: String = ""

    /// Buffer for the model turn currently being assembled from streamed chunks.
    private var currentModelTurn: String = ""

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let timeStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Lifecycle

    /// Begin a new session log file. Any previous session is finalized first.
    func startSession() {
        endSession()

        GeminiLiveStoragePaths.prepare()
        let dir = GeminiLiveStoragePaths.transcriptsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "session-\(Self.filenameFormatter.string(from: Date())).md"
        fileURL = dir.appendingPathComponent(filename)
        loggedLastUserText = ""
        pendingUserText = ""
        currentModelTurn = ""

        let header = """
        # Notch Live Session

        Started at \(Self.isoFormatter.string(from: Date()))

        ---

        """
        appendRaw(header)
    }

    /// Flush pending buffers and close the active log file.
    func endSession() {
        flushUserIfPending()
        flushModelTurn()
        if fileURL != nil {
            appendRaw("\n---\n\n_Session ended at \(Self.isoFormatter.string(from: Date()))_\n")
        }
        fileURL = nil
        pendingUserText = ""
        currentModelTurn = ""
        loggedLastUserText = ""
    }

    // MARK: - User events

    /// Update the in-flight user voice transcript (replaces, doesn't append).
    func setPendingUserText(_ text: String) {
        guard fileURL != nil else { return }
        pendingUserText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commit a user message immediately (typed input goes through this).
    func recordUserText(_ text: String) {
        guard fileURL != nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The pending voice transcript is superseded by the explicit text input.
        pendingUserText = ""
        guard trimmed != loggedLastUserText else { return }
        appendRaw("**User** _[\(Self.timeStampFormatter.string(from: Date()))]_\n\n\(trimmed)\n\n")
        loggedLastUserText = trimmed
    }

    /// Persist the buffered voice transcript if one is waiting.
    func flushUserIfPending() {
        guard fileURL != nil else { return }
        let text = pendingUserText
        pendingUserText = ""
        guard !text.isEmpty, text != loggedLastUserText else { return }
        appendRaw("**User** _[\(Self.timeStampFormatter.string(from: Date()))]_\n\n\(text)\n\n")
        loggedLastUserText = text
    }

    // MARK: - Model events

    /// Append a streamed model chunk. `isNewTurn` flushes any buffered prior turn first
    /// (matches the same boundary semantics used by the displayed transcript).
    func appendModelChunk(_ chunk: String, isNewTurn: Bool) {
        guard fileURL != nil else { return }
        if isNewTurn {
            flushModelTurn()
            currentModelTurn = chunk
        } else if currentModelTurn.isEmpty {
            currentModelTurn = chunk
        } else {
            currentModelTurn += " " + chunk
        }
    }

    /// Write the buffered model turn to disk and reset the buffer.
    func flushModelTurn() {
        guard fileURL != nil else { return }
        let trimmed = currentModelTurn.trimmingCharacters(in: .whitespacesAndNewlines)
        currentModelTurn = ""
        guard !trimmed.isEmpty else { return }
        appendRaw("**Model** _[\(Self.timeStampFormatter.string(from: Date()))]_\n\n\(trimmed)\n\n")
    }

    // MARK: - File I/O

    private func appendRaw(_ text: String) {
        guard let fileURL else { return }
        let url = fileURL
        let payload = text
        Self.writeQueue.async {
            guard let data = payload.data(using: .utf8) else { return }
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } catch {
                        // Best-effort: drop on disk error rather than crash the session.
                    }
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
