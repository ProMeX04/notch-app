import Foundation
import NotchBridgeParserCore

// MARK: - Frame building helpers

/// Build an unmasked WebSocket text frame (server → client direction).
func makeTextFrame(payload: Data, fin: Bool = true, opcode: UInt8 = 0x01) -> Data {
    var frame = Data()
    let firstByte: UInt8 = (fin ? 0x80 : 0x00) | opcode
    frame.append(firstByte)

    if payload.count < 126 {
        frame.append(UInt8(payload.count))
    } else if payload.count <= Int(UInt16.max) {
        frame.append(126)
        frame.append(UInt8(payload.count >> 8))
        frame.append(UInt8(payload.count & 0xFF))
    } else {
        frame.append(127)
        let len = UInt64(payload.count)
        for shift in stride(from: 56, through: 0, by: -8) {
            frame.append(UInt8((len >> UInt64(shift)) & 0xFF))
        }
    }
    frame.append(payload)
    return frame
}

/// Build a masked WebSocket text frame (client → server direction).
func makeMaskedTextFrame(payload: Data, mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]) -> Data {
    var frame = Data()
    frame.append(0x81) // FIN + opcode text
    // Set mask bit + payload length (only handles < 126 for simplicity in tests)
    frame.append(0x80 | UInt8(payload.count))
    frame.append(contentsOf: mask)
    for (i, byte) in payload.enumerated() {
        frame.append(byte ^ mask[i % 4])
    }
    return frame
}

/// Build a ping frame.
func makePingFrame(payload: Data = Data()) -> Data {
    var frame = Data()
    frame.append(0x89) // FIN + opcode ping
    frame.append(UInt8(payload.count))
    frame.append(contentsOf: payload)
    return frame
}

/// Build a close frame.
func makeCloseFrame() -> Data {
    Data([0x88, 0x00]) // FIN + opcode close, zero-length payload
}

/// Build a continuation frame.
func makeContinuationFrame(payload: Data, fin: Bool) -> Data {
    makeTextFrame(payload: payload, fin: fin, opcode: 0x00)
}

// MARK: - Assertion helpers

enum TestError: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self { case .assertion(let msg): return msg }
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
    if actual != expected {
        throw TestError.assertion(
            "Expected \(expected), got \(actual)\(message.isEmpty ? "" : " — \(message)")"
        )
    }
}

func assertTrue(_ condition: Bool, _ message: String = "") throws {
    if !condition {
        throw TestError.assertion(message.isEmpty ? "Expected true" : message)
    }
}

// MARK: - Tests

enum FrameParserTests {

    // ── 1. Single complete unmasked text frame ────────────────────────────────

    static func singleCompleteUnmaskedTextFrame_decodesResult() throws {
        let json = #"{"type":"browser-command-result","id":"abc123","success":true,"result":{}}"#
        let payload = Data(json.utf8)
        let frameData = makeTextFrame(payload: payload)

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frameData
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 1, "expected 1 message")
        guard case .text(let data) = messages[0] else {
            throw TestError.assertion("expected .text message")
        }
        try assertEqual(data, payload, "payload mismatch")
        // Buffer should be fully consumed.
        try assertTrue(parser.receiveBuffer.isEmpty, "receiveBuffer should be empty after drain")
    }

    // ── 2. Masked client text frame ───────────────────────────────────────────

    static func maskedClientTextFrame_decodesResult() throws {
        let json = #"{"type":"browser-command-result","id":"xyz","success":false,"result":{}}"#
        let payload = Data(json.utf8)
        let mask: [UInt8] = [0xAB, 0xCD, 0xEF, 0x01]
        let frameData = makeMaskedTextFrame(payload: payload, mask: mask)

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frameData
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 1, "expected 1 message")
        guard case .text(let data) = messages[0] else {
            throw TestError.assertion("expected .text message")
        }
        try assertEqual(data, payload, "masked payload decoded incorrectly")
    }

    // ── 3. Fragmented text message across continuation frames ─────────────────

    static func fragmentedTextMessage_acrossContinuationFrames_assembles() throws {
        let fullText = "Hello, fragmented world!"
        let fullData = Data(fullText.utf8)
        let midpoint = fullData.count / 2
        let part1 = fullData.prefix(midpoint)
        let part2 = fullData.suffix(from: midpoint)

        // First frame: FIN=false, opcode=text
        let frame1 = makeTextFrame(payload: Data(part1), fin: false)
        // Second frame: FIN=true, opcode=continuation
        let frame2 = makeContinuationFrame(payload: Data(part2), fin: true)

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frame1 + frame2
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 1, "expected 1 reassembled message")
        guard case .text(let data) = messages[0] else {
            throw TestError.assertion("expected .text message")
        }
        try assertEqual(data, fullData, "reassembled payload mismatch")
    }

    // ── 4. Ping frame surfaces pong path ──────────────────────────────────────

    static func pingFrame_doesNotCrash_surfacesPongPath() throws {
        let pingPayload = Data("ping-data".utf8)
        let frameData = makePingFrame(payload: pingPayload)

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frameData
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 1, "expected 1 message (ping)")
        guard case .ping(let data) = messages[0] else {
            throw TestError.assertion("expected .ping message, got \(messages[0])")
        }
        // Caller should echo this data back as a pong frame.
        try assertEqual(data, pingPayload, "ping payload mismatch")
    }

    // ── 5. Oversized payload is rejected ──────────────────────────────────────

    static func oversizedPayload_isRejected() throws {
        // Build a frame header claiming a 3 MB payload (exceeds 2 MB default limit).
        let oversizeLen: UInt64 = 3 * 1024 * 1024
        var frame = Data()
        frame.append(0x81)   // FIN + text
        frame.append(127)    // 8-byte extended length
        for shift in stride(from: 56, through: 0, by: -8) {
            frame.append(UInt8((oversizeLen >> UInt64(shift)) & 0xFF))
        }
        // Don't append actual payload bytes — the parser should reject on the header.

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frame
        let messages = parser.drainMessages()

        // Parser should return nothing (and not crash).
        try assertEqual(messages.count, 0, "oversized frame should be silently dropped")
    }

    // ── 6. Malformed extended-length frame is rejected ────────────────────────

    static func malformedExtendedLengthFrame_isRejected() throws {
        // A frame that claims 16-bit length but provides only 1 byte of length data.
        var frame = Data()
        frame.append(0x81)  // FIN + text
        frame.append(126)   // signals 2-byte length follows
        frame.append(0xFF)  // only 1 byte instead of 2 — malformed

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frame
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 0, "malformed extended-length frame should be incomplete/rejected")
    }

    // ── 7. Close frame surfaces close message ─────────────────────────────────

    static func closeFrame_surfacesCloseMessage() throws {
        let frameData = makeCloseFrame()

        var parser = BrowserBridgeFrameParser()
        parser.receiveBuffer = frameData
        let messages = parser.drainMessages()

        try assertEqual(messages.count, 1, "expected 1 message (close)")
        guard case .close = messages[0] else {
            throw TestError.assertion("expected .close message, got \(messages[0])")
        }
    }

    // ── 8. Continuation frame completion produces exactly one message ──────────

    static func continuationFrameCompletion_producesExactlyOneMessage() throws {
        // Three-part fragmented message.
        let parts = ["foo", "bar", "baz"].map { Data($0.utf8) }
        let expected = Data("foobarbaz".utf8)

        let frame1 = makeTextFrame(payload: parts[0], fin: false, opcode: 0x01) // start
        let frame2 = makeContinuationFrame(payload: parts[1], fin: false)
        let frame3 = makeContinuationFrame(payload: parts[2], fin: true)        // final

        var parser = BrowserBridgeFrameParser()

        // Feed one fragment at a time to simulate incremental arrival.
        parser.receiveBuffer.append(frame1)
        let msgs1 = parser.drainMessages()
        try assertEqual(msgs1.count, 0, "intermediate frame must not produce a message")

        parser.receiveBuffer.append(frame2)
        let msgs2 = parser.drainMessages()
        try assertEqual(msgs2.count, 0, "intermediate frame must not produce a message")

        parser.receiveBuffer.append(frame3)
        let msgs3 = parser.drainMessages()
        try assertEqual(msgs3.count, 1, "final continuation frame must produce exactly 1 message")

        guard case .text(let data) = msgs3[0] else {
            throw TestError.assertion("expected .text message")
        }
        try assertEqual(data, expected, "reassembled payload mismatch")
    }
}
